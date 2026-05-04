# nocfsaccessd

**nocfsaccessd**는 Sirius 프로토콜의 파일 시스템 액세스 (`fsaccess` / `fsaccess_mount` 채널) 기능을
사용자 머신의 Finder 등에 NFS 마운트로 노출하기 위한 보조 데몬입니다.

```
 [Noctiluca Server (host app)]    XPC    [nocfsaccessd]    NFSv4    [Finder / Other Apps]
                              ─────────►              ─────────►
                              ◄─────────              ◄─────────
                              callbacks               (mount @ ~/NoctilucaFS)
```

호스트 앱(현재는 Noctiluca Server 단독)이 시작될 때 자식 프로세스로 띄우고,
호스트 앱이 종료되면 같이 정리됩니다.
독립적으로 실행 가능한 launchd daemon이나 LaunchAgent가 아니며,
시스템에 별도로 등록되지 않습니다.

> **버전 / 상태**: 본 문서는 `nocfsaccessd`의 1차 설계 결정을 정본으로 묶기 위한 문서입니다.
> 실제 구현이 본 문서와 어긋나면, 본 문서가 우선합니다 (구현이 따라옵니다).

---

# 1. 왜 데몬으로 분리하는가

Sirius 프로토콜의 fsaccess 채널들은 본질적으로 호스트 앱 안에서도 처리할 수 있습니다.
그럼에도 nocfsaccessd라는 별도 프로세스를 두는 이유는 다음과 같습니다.

- **macOS의 NFS 서버 노출이 곧 "프로세스 단위"이기 때문에**:
  loopback NFS 서버 (`nanonfs`) 를 한 프로세스가 들고, 그 프로세스가 listen하는 포트를
  `mount_nfs` (또는 NetFS API) 가 마운트합니다. 호스트 앱과 NFS 서버 라이프사이클이
  지나치게 결합되면 디버깅과 cleanup이 까다로워집니다 — 별도 프로세스로 두면
  "마운트 / NFS / NFS handle 캐시 / 가상 트리" 와 "Sirius 채널 / 인증 / 정책" 의
  관심사를 자연스럽게 가른다.

- **다중 클라이언트(접속) 분리**:
  하나의 호스트 앱이 동시에 여러 navigator 접속을 받을 수 있고, 각 접속마다 독립적인
  fsaccess 마운트 세션이 생깁니다. 단일 NFS 서버에서 가상 디렉토리 트리로 묶어서
  노출하는 편이 사용자 경험과 마운트 cleanup 양쪽에서 가장 단순합니다.

- **향후 Noctiluca Navigator (호스트 앱이 server role을 가지지 않음에도 fsaccess가 필요한
  시나리오) 에서도 같은 데몬을 재사용할 수 있도록**:
  현 단계에서는 Server.app만 사용하지만, 데몬-호스트 인터페이스가 잘 분리되어 있으면
  같은 binary가 양쪽에서 spawn 가능합니다.

비목표 (non-goals):

- 시스템 전체에 노출되는 NFS 서버. **루프백 전용**이며, 외부 인터페이스 바인딩을 의도적으로
  하지 않습니다 (`nanonfs` 의 `Bind.loopback` 사용).
- root 권한으로 동작하는 setuid helper. nocfsaccessd는 **사용자 권한**으로 동작합니다.
- launchd LaunchAgent / LaunchDaemon 등록. 호스트 앱이 직접 spawn하고 직접 종료시킵니다.
- 단독 실행 / 디버그 모드. 항상 호스트 앱이 spawn한다고 가정하며, XPC endpoint가 주어지지
  않으면 즉시 abort합니다.

---

# 2. 컴포넌트와 책임 분담

본 표는 **host (consuming peer)** 측 책임만 정리합니다. host 는 navigator 가 노출하는
파일을 자기 머신의 Finder 에 NFS 로 띄우려는 *요청자* 입니다. navigator (exposing peer)
측 책임 — 노출 entries 등록, consent UX, POSIX wrapper / FileSystemErrorCode 매핑
— 은 NoctilucaClient 의 fsaccess 모듈 (`FSAccessChannel` /
`FSAccessMountChannel` / `FSAccessConsentBroker` / `FSAccessPathValidator` /
`FSAccessErrorMapper`) 이 담당하며 본 문서의 범위 밖입니다.

| 책임 | 담당 |
|---|---|
| Sirius `fsaccess` control channel **발신** (List / Mount / Unmount 요청 송신, 응답 수신) | **호스트 앱** |
| Sirius `fsaccess_mount` data channel **발신** (Open / Read / Write / ReadDir / ... 요청 송신) | **호스트 앱** |
| 어떤 navigator connection 의 어떤 entry 를 자동 마운트할지 결정 (allowedConnections / Mount 트리거 정책) | **호스트 앱** |
| Sirius 인증 (AuthChallenge / AuthRequest / AuthResponse) 및 username 추출 | **호스트 앱** |
| NFS 서버 운영 (nanonfs 인스턴스, file handle 발급, 가상 디렉토리 트리) | **nocfsaccessd** |
| ~/NoctilucaFS 마운트 / 언마운트 (NetFS API 호출) | **호스트 앱** |
| Stale mount cleanup (startup probe) | **호스트 앱** |
| 호스트 앱 ↔ 데몬 IPC | **양쪽** (NSXPCConnection) |

핵심 원칙: **데몬은 Sirius 프로토콜을 모릅니다.** 데몬은 nanonfs의 `NFSServer` 콜백
(lookup, getattr, read, write, readdir, ...) 을 구현하면서 매 콜백마다 XPC를 통해 호스트 앱에
"이 경로의 entry를 stat 좀 해줘 / 이 범위를 읽어줘" 라고 묻습니다. 호스트 앱이 그 요청을
받아 적절한 fsaccess_mount 메시지로 변환해 navigator에 보내고, 응답을 다시 데몬에게 돌려줍니다.

이 분담의 결과:

- 데몬은 nanonfs와 XPC interface 정의(상대 측 SiriusKit msgdef DTO를 NSData로 받는 정도)만
  알면 되며, fsaccess control channel의 단일 인스턴스 제약, 인증 시점, 정책 같은 영역은
  전부 호스트 앱이 책임집니다.
- 호스트 앱은 NFS handle / NFS request flow를 모릅니다. 데몬이 알아서 NFS handle을 발급하고
  매핑을 보유합니다.

---

# 3. 라이프사이클 (Spawn → Shutdown)

```
[Server.app launched]
        │
        ├─ NSXPCListener.anonymous() → endpoint
        ├─ Posix_spawn nocfsaccessd
        │     env: NOC_FSACCESSD_XPC_ENDPOINT=<base64-encoded NSSecureCoding>
        │     argv[0]: <Server.app>/Contents/MacOS/nocfsaccessd
        │
        ├─ daemon decodes endpoint, NSXPCConnection.connect
        ├─ daemon starts nanonfs on port:0 (OS-assigned)
        ├─ daemon reports actual port via XPC
        │
        ├─ host app probes ~/NoctilucaFS
        │     - missing            → mkdir
        │     - exists & empty     → reuse
        │     - exists & is mount  → forced umount, then reuse
        │     - exists & not empty → dialog: "비워주세요" / disable fsaccess feature
        │
        ├─ host app NetFSMountURLAsync(nfs://localhost:<port>/, ~/NoctilucaFS)
        │
        ├─ (idle) — empty virtual tree, _README.txt visible
        │
        ├─ navigator connects, fsaccess channel opens, mount session approved
        │     - host app pushes "session added" XPC event to daemon
        │     - daemon updates virtual tree root, hides _README.txt
        │
        ├─ ... (callbacks flow over XPC) ...
        │
        ├─ navigator disconnects / mount session released
        │     - host app pushes "session removed" event
        │     - daemon updates virtual tree root, restores _README.txt if root empty
        │
        ▼
[Server.app quit]
        ├─ host app NetFSUnmount(~/NoctilucaFS) — forced if needed
        ├─ host app sends shutdownGracefully XPC to daemon
        ├─ host app waits up to 5s for daemon exit
        ├─ if alive: SIGTERM, wait up to 5s
        └─ if alive: SIGKILL
```

호스트 앱이 crash하더라도 다음 실행의 startup probe (위 "exists & is mount → forced umount") 가
잔재 마운트를 자동 정리합니다.

---

# 4. IPC (Inter-Process Communication)

## 4.1. 메커니즘

- **NSXPCConnection** (anonymous endpoint).
- 호스트 앱이 `NSXPCListener.anonymous()` 로 listener를 만들고, listener의 `endpoint`를
  `NSKeyedArchiver` 로 직렬화 → base64 인코딩 → 환경변수 `NOC_FSACCESSD_XPC_ENDPOINT` 로
  자식 프로세스에 전달.
- nocfsaccessd는 시작 시 환경변수에서 endpoint를 디코드하고, `NSXPCConnection(listenerEndpoint:)`
  로 reverse-connect.
- 환경변수가 비어있거나 디코드 실패면 데몬은 즉시 abort (`exit(EX_USAGE)`).

> ps에 노출되지 않도록 argv가 아닌 환경변수를 사용합니다.
> NSXPCListener.Endpoint는 capability 객체 자체이므로, 부모-자식 간 환경변수 전달 안에서는
> 누설 위험이 미미합니다 (다만 child의 `posix_spawnattr` 에 `POSIX_SPAWN_SETSIGMASK` 등
> 표준적인 sanitization을 함께 적용해 환경변수가 후속 자식으로 propagate 되지 않도록 합니다).

## 4.2. NSXPCInterface 메서드 표면

XPC 인터페이스는 **NSXPCInterface (ObjC 프로토콜)** 로 정의합니다.

인자/리턴 중 단순 스칼라(`UInt64`, `String`, `Data` 등) 가 아닌 복합 payload는 별도 shared
모듈 **`NocFSAccessXPC`** 가 정의하는 **`NSSecureCoding`-conformant `@objc` 클래스**로
주고받습니다. NSXPC가 자동으로 직렬화/역직렬화하므로 메서드 시그니처는 `...Data:` 같은
`NSData` 래핑 없이 타입을 그대로 노출합니다.

> **데몬은 SiriusKitCore에 의존하지 않습니다.** 데몬의 Noctiluca-side 의존은
> `NocFSAccessXPC` 단 한 개로 한정되며, Sirius msgdef ↔ XPC DTO 변환은 호스트 앱이
> 단독 책임집니다. 이로써 섹션 2의 *"데몬은 Sirius 프로토콜을 모른다"* 원칙이 컴파일러
> 수준에서 강제됩니다.
>
> 비용은 Sirius msgdef와 XPC DTO 두 스키마를 동기화 유지해야 한다는 점이지만, 양쪽
> 모두 본인이 관리하는 코드라 drift 위험은 관리 가능한 수준이라고 보고 받아들입니다.

`NocFSAccessXPC` 가 노출하는 주요 DTO (구체 필드는 구현 시점에 확정):

- `NocFSMountSessionDescriptor` — `(connectionLabel, mountSessionId, displayName, grantedAccess, ...)`
- `NocFSFileStat` — `getattr` / `setattr` / `open` 응답에서 사용
- `NocFSAttributesPatch` — `setattr` 입력
- `NocFSAttributesInit` — `create` 입력
- `NocFSDirEntry` — `readdir` 응답 항목

요약된 메서드 목록 (세부 시그니처는 구현 시점에 확정):

### 4.2.1. host → daemon (`NocFSAccessDaemonProtocol`)

| 메서드 | 의도 |
|---|---|
| `daemonReady(replyPort:reply:)` | 핸드셰이크. 데몬이 nanonfs를 listen 상태로 만든 직후 host가 호출하고, 데몬이 실제 NFS port를 리턴. |
| `addMountSession(descriptor:reply:)` | 가상 트리 root 아래에 새 mount session entry를 추가. `descriptor: NocFSMountSessionDescriptor` 가 `(connectionLabel, mountSessionId, displayName, grantedAccess, ...)` 를 담음. |
| `removeMountSession(mountSessionId:reply:)` | 마운트 세션 제거. 데몬은 관련 file handle을 모두 invalidate. |
| `addConnection(connectionLabel:displayName:reply:)` | 가상 트리 1단계 namespace 항목 추가 (예: `0001-cheesekun`). |
| `removeConnection(connectionLabel:reply:)` | 1단계 namespace 항목 제거 (해당 connection의 모든 mount session도 cascade로 제거). |
| `shutdownGracefully(reply:)` | umount 완료 후 호스트 앱이 호출. 데몬은 nanonfs run loop을 정지하고 self-exit. |

### 4.2.2. daemon → host (`NocFSAccessHostProtocol`, reverse interface)

데몬은 NFS callback 처리 중 매 callback마다 호스트에 질의합니다. 모든 메서드는 비동기이며
`reply:` 핸들러로 응답을 받습니다.

| 메서드 | nanonfs callback 매핑 |
|---|---|
| `lookup(mountSessionId:parentHandleId:name:reply:)` | `lookup(parent:name:)` |
| `lookupParent(mountSessionId:handleId:reply:)` | `lookupParent(of:)` |
| `getattr(mountSessionId:handleId:reply:)` | `getattr(handle:)` / `fStat` |
| `setattr(mountSessionId:handleId:patch:reply:)` | `setattr(handle:stateid:patch:)` (patch: `NocFSAttributesPatch`) |
| `access(mountSessionId:handleId:mask:reply:)` | `access(handle:mask:)` |
| `readdir(mountSessionId:handleId:cookie:cookieVerifier:maxEntries:reply:)` | `readdir(handle:cookie:...)` |
| `readlink(mountSessionId:handleId:reply:)` | `readlink(handle:)` |
| `open(mountSessionId:parentHandleId:name:share:deny:createMode:reply:)` | `open(parent:name:...)` |
| `close(mountSessionId:handleId:reply:)` | `close(handle:stateid:)` |
| `read(mountSessionId:handleId:offset:length:reply:)` | `read(handle:stateid:offset:count:)` |
| `write(mountSessionId:handleId:offset:data:stability:reply:)` | `write(handle:stateid:offset:stability:data:)` |
| `commit(mountSessionId:handleId:offset:length:reply:)` | `commit(handle:offset:count:)` |
| `create(mountSessionId:parentHandleId:name:type:attrs:reply:)` | `create(parent:name:type:attrs:)` (attrs: `NocFSAttributesInit`) |
| `remove(mountSessionId:parentHandleId:name:reply:)` | `remove(parent:name:)` |
| `rename(mountSessionId:srcParentHandleId:srcName:dstParentHandleId:dstName:reply:)` | `rename(...)` |
| `link(mountSessionId:targetHandleId:parentHandleId:name:reply:)` | `link(...)` |

호스트 앱은 각 호출을 fsaccess_mount channel의 적절한 메시지(`FileSystemOpenRequest`,
`FileSystemReadRequest`, ...) 로 번역해 navigator에 보내고, 응답이 도착하면 reply 핸들러로
돌려줍니다.

> nanonfs의 OPEN / CLOSE / LOCK 등 stateful path는 현 단계에서 모두 daemon → host로
> 위임되며, host는 fsaccess_mount의 OPEN/CLOSE/READ/WRITE 호출 시퀀스로 번역합니다.
> NFSv4의 stateid 자체는 데몬 내부에서 보유 / 발급하며, 호스트 앱에는 노출되지 않습니다.

## 4.3. 모든 callback이 XPC round-trip이라는 점

데이터 흐름 단순화를 우선해서 **mmap / shared memory를 사용하지 않습니다**. NFSv4의 기본
read 청크 크기 (~64 KiB) 가 macOS loopback XPC + Sirius 채널의 처리 한계 안에서 충분히
빠르다고 가정합니다. 대용량 read/write에서 병목이 측정되면, fsaccess의 streaming 경로
(`FileSystemRequestStreamRead` / `FileSystemRequestStreamWrite`) 와 데몬 측 buffered fast path를
이후에 추가하는 옵션을 열어둡니다.

---

# 5. NFS 서버 (nanonfs)

- **라이브러리**: `nanonfs` (Swift Package, `~/works/noctiluca/nanonfs` 참조).
  자세한 API는 nanonfs의 README가 정본입니다.
- **바인딩**: `NFSBind.loopback(port: 0)` — OS가 high port를 자동 할당합니다.
  데몬은 listener가 바인딩된 직후 `boundAddress` 의 포트 번호를 호스트 앱에 XPC로 보고합니다.
- **외부 노출 금지**: 외부 인터페이스 바인딩 (`NFSBind.external`) 은 사용하지 않습니다.
- **인증**: AUTH_SYS만 수락 (nanonfs 기본 동작). loopback이라는 가정 하에 추가 인증은
  두지 않습니다.

## 5.1. 가상 디렉토리 트리

```
nfs://localhost:<port>/                    ← 마운트 root (NFS PUTROOTFH)
├── _README.txt                            ← 가상 트리에 active connection이 0개일 때만 노출
├── 0001-cheesekun/                        ← Sirius connection 1단계 namespace
│   ├── 내 문서/                            ← FileSystemEntry.name (sanitize 적용)
│   │   ├── ...
│   │   └── ...
│   └── Blender 작업물/
│       └── work1.blend
└── 0002-cheesekun/                        ← 같은 사용자가 두 번째로 접속한 connection
    └── Music/
```

### 5.1.1. 1단계: connection label `NNNN-username`

- **NNNN**: 데몬 시작 이후 monotonic 4-digit zero-padded 카운터. 데몬이 발급해서 호스트 앱에
  통보 (또는 호스트 앱이 발급해서 add 시 함께 전달 — 구현 시점에 확정). 5자리 이상은
  실용 한도 밖이라 가정.
- **username**: Sirius 인증 후 호스트 앱이 결정. 기본 추출 출처는 `AuthRequest.method` /
  `AuthRequest.payload` (예: 패스워드 인증의 경우 username). 추출 불가 시 `unknown` fallback.
- **충돌 방지**: 같은 사용자가 여러 번 접속해도 NNNN이 다르므로 자연스럽게 구분됩니다.
  연결 종료 후에도 NNNN은 재사용하지 않습니다.

### 5.1.2. 2단계: mount session entry name

- 호스트 앱이 fsaccess control channel에서 `FileSystemMountResponse(success=true)` 를 보낸 후
  데몬에 `addMountSession` 을 호출할 때, 그 mount session에 대응하는 `FileSystemEntry.name`
  (`내 문서`, `~/Documents` 등) 을 함께 넘깁니다.
- 데몬은 이 name을 NFS 디렉토리 entry name으로 그대로 사용하되, 다음과 같이 sanitize:
  - `/` → `_`
  - NUL (`U+0000`) → `_`
  - 같은 1단계 디렉토리 안에서 중복되면 `name (2)`, `name (3)` 등 suffix를 붙임.

### 5.1.3. 빈 트리 / `_README.txt`

active connection이 0개인 동안 가상 트리 root에는 `_README.txt` 한 개만 노출됩니다.
내용은 정적 텍스트:

```
이 폴더는 Noctiluca의 원격 파일 공유 기능을 위해 마운트되었습니다.

원격 클라이언트가 접속하여 파일을 공유하면, 이 README는 자동으로 사라지고
공유된 항목들이 이 폴더 아래에 나타납니다.

자세한 내용은 https://... 를 참조하세요.
```

다국어 (ko / en) 본문을 UTF-8 BOM 없이 한 파일에 묶어 두며, 첫 connection이 추가되는
순간 root listing에서 사라집니다 (open 중이었으면 후속 read는 `ESTALE` 로 응답).

## 5.2. NFS file handle 발급 / 매핑

- **데몬이 file handle을 자체 발급**합니다. nanonfs의 `NFSFileHandle` opaque blob 안에는
  데몬 내부 식별자 (예: `(mountSessionId, internalEntryId)` 의 인코딩) 만 들어 있고,
  NFS 클라이언트는 이 blob을 그대로 다시 돌려보냅니다.
- 데몬은 내부에 `(NFSFileHandle → (mountSessionId, normalizedPath))` 매핑 테이블을 보유합니다.
  매 lookup마다 호스트 앱에 XPC로 stat을 질의해 새 handle을 발급하고 매핑에 등록합니다.
- 매핑 테이블은 데몬 메모리에만 존재하며 영속화하지 않습니다. 데몬이 재시작되면 모든
  handle은 자연스럽게 `staleHandle` 로 응답됩니다.
- mount session이 제거되면 (`removeMountSession`) 해당 session에 속한 모든 handle을 즉시
  invalidate하고 후속 요청을 `staleHandle` 로 응답합니다.

> NFSv4의 OPEN stateid는 데몬 내부에서만 의미를 가집니다. 호스트 앱은 fsaccess_mount의
> `handleId` (uint64) 만 알고, 데몬은 그 handleId와 자체 stateid를 매핑하여 보관합니다.

---

# 6. 마운트 / 언마운트 (NetFS API)

## 6.1. 호출 주체

- **호스트 앱**이 `NetFS.framework` 의 `NetFSMountURLAsync` 를 호출합니다.
  데몬은 NFS 서버 listen만 책임지고, 마운트 자체에는 관여하지 않습니다.
- 마운트는 **사용자 권한**으로 수행됩니다. NetFS API는 user-level mount를 지원하므로
  setuid root helper나 `vfs.usermount` sysctl 변경이 필요하지 않습니다.

## 6.2. URL / 경로

| 항목 | 값 |
|---|---|
| URL | `nfs://localhost:<dynamic-port>/` |
| Mount point | `~/NoctilucaFS` (사용자 home directory 직속) |
| Mount options | `vers=4,resvport=0,soft,intr,nolocks` |

> `nolocks` 는 nanonfs가 NFSv4 byte-range lock을 제한적으로 지원하는 단계 동안 default로 둡니다.
> Phase 진행에 따라 옵션은 조정될 수 있습니다.

## 6.3. Mount point 사전 점검 / 생성

호스트 앱 startup 시:

1. `~/NoctilucaFS` 가 **존재하지 않으면**: `mkdir(0o755)` 로 생성.
2. **존재하고 mount point**이면: 이전 실행의 stale 마운트로 간주, `unmount(MNT_FORCE)`
   호출 후 빈 디렉토리로 reset.
3. **존재하고 일반 빈 디렉토리**이면: 그대로 재사용.
4. **존재하고 빈 디렉토리가 아니면**: 사용자 데이터를 덮을 위험이 있으므로 마운트하지 않고
   호스트 앱 UI에 다이얼로그 표시 — "`~/NoctilucaFS` 가 비어있지 않아 파일 공유 기능을
   사용할 수 없습니다. 폴더를 비우거나 다른 위치로 옮기세요." fsaccess feature는
   **비활성화** 상태로 남고, ServerHello.supportedFeatures 에서 fsaccess가 제외됩니다.

## 6.4. Unmount

- 호스트 앱 정상 종료 시 `NetFSUnmountURL` 또는 `unmount(MNT_FORCE)` 로 언마운트한 뒤
  데몬에 `shutdownGracefully` XPC 호출 → 데몬 self-exit 대기.
- 호스트 앱 비정상 종료 시 마운트가 남을 수 있으나, 다음 실행의 startup probe (위 6.3)에서
  자동 정리됩니다.

---

# 7. 동적 갱신 (Push 모델)

데몬은 가상 트리의 1단계 / 2단계 구조를 **호스트 앱의 push event**로만 갱신합니다.
데몬이 호스트에 "현재 active한 connection / mount session 목록 줘" 라고 polling하지 않습니다.

| 이벤트 | 트리거 | 데몬의 반응 |
|---|---|---|
| Sirius 인증 완료 + fsaccess channel open | host → `addConnection(connectionLabel, displayName)` | 가상 트리 root에 1단계 디렉토리 생성. `_README.txt` 가 있었으면 hide. |
| FileSystemMountResponse(success=true) | host → `addMountSession(...)` | 1단계 디렉토리 아래에 2단계 entry 생성. |
| FileSystemUnmountRequest 처리 완료 / fsaccess_mount channel close | host → `removeMountSession(...)` | 2단계 entry 제거. 관련 file handle invalidate. |
| Sirius connection close / fsaccess control channel close | host → `removeConnection(...)` | 1단계 디렉토리 + 그 안의 모든 mount session 제거. root에 connection이 0개가 되면 `_README.txt` 다시 노출. |

**일관성**: push event 처리는 데몬 내부에서 직렬화 (actor 또는 단일 dispatch queue) 되어
가상 트리 상태와 NFS 응답이 race 없이 변경됩니다. NFS 클라이언트가 readdir 중에
add/remove가 발생할 수 있으나, 이는 NFS의 일반적인 동시 수정 시멘틱(`NFS4ERR_NOT_SAME` 또는
정합성 보장 없음)과 동일하게 처리합니다.

---

# 8. 인증 / Consent UX

## 8.1. Sirius 인증 (호스트 앱 책임)

- fsaccess 관련 채널은 Sirius 인증이 끝난 뒤에만 open될 수 있다는 mdproto의 phase
  constraint를 그대로 따릅니다.
- 호스트 앱은 인증 성공 시 `(connectionLabel, displayName=username)` 을 결정해 데몬에
  `addConnection` 호출. username 출처는 `AuthRequest` 의 method/payload에서 호스트 앱이
  추출하며, 추출 불가 시 `unknown` fallback.

## 8.2. Mount 트리거 / 어떤 entry 를 마운트할지 (호스트 앱 책임)

- 호스트는 *요청자* 입니다. List 응답으로 받은 `FileSystemEntry[]` 중 어느 항목에 대해
  `FileSystemMountRequest` 를 발신할지 결정합니다.
- 정책은 호스트 앱의 Settings UI ("File System Access" 탭) 에서 connection 단위로 관리:
  - `alwaysAllow` (또는 read-only): connect 직후 List → 모든 entry 자동 Mount.
  - `alwaysAsk`: List 응답을 받으면 macOS notification / 메뉴바 알림으로 사용자에게
    선택지를 제시한 뒤 Mount 발신.
  - `deny`: 해당 connection 에 대해서는 List / Mount 발신 자체를 안 함 (fsaccess feature
    가 ServerHello.supportedFeatures 에서 빠져나가지는 않음 — 채널을 열지 않을 뿐).
- consent prompt — *"이 navigator 의 폴더 X 에 접근해도 되겠습니까?"* — 는 navigator 측
  책임 (`FSAccessConsentBroker`) 이며 host 는 prompt 를 띄우지 않습니다. host 측 동의는
  Settings 정책으로만 표현합니다.
- `FileSystemMountResponse(success=false, code=consentDenied)` 를 받으면 host 는 해당
  entry 를 다시 시도하지 않고 (다음 connect 까지) 사용자에게 알림으로 알립니다.

## 8.3. 노출 entries 의 출처

- 호스트는 *노출 측이 아닙니다*. 어떤 폴더를 노출할지 결정하는 것은 navigator
  (exposing peer) 의 책임입니다. NoctilucaClient 의 `SessionSettings.fsAllowedEntries`
  + `FSAccessChannel` 의 `findExposedEntry` 가 이 역할을 합니다.
- 따라서 host 측 Settings 의 "File System Access" 탭에는 *노출할 폴더* 항목이 없습니다.
  host 측 Settings 가 다루는 것은 다음 정책 뿐입니다:
  - **mount point 위치** (기본 `~/NoctilucaFS`)
  - **fsaccess feature on/off**
  - **allowedConnections** (어떤 connection username / fingerprint 에 대해 어떤
    consentPolicy 를 적용할지)
- `FileSystemListResponse.entries` 는 navigator 가 채워서 host 에 보내는 *응답* 입니다.
  host 는 이 entries 를 그대로 가상 트리의 2단계 namespace 후보로 보유하며, §8.2 의
  정책에 따라 실제 Mount 를 트리거합니다.

---

# 9. 로깅

- **`os.Logger`** 직접 사용. subsystem: `pl.unstabler.noctiluca.fsaccessd`.
- 데몬이 SiriusKitCore에 의존하지 않으므로 SiriusKit의 Logger 인프라는 사용하지 않습니다.
- 권장 categories: `lifecycle` / `xpc` / `nfs` / `mount` / `vtree`.
- Console.app 또는 `log show --predicate 'subsystem == "pl.unstabler.noctiluca.fsaccessd"'`
  로 추출 가능.
- 호스트 앱은 자체 subsystem (`pl.unstabler.noctiluca.server` 등) 을 쓰므로 두 프로세스의
  로그를 함께 보려면 `subsystem BEGINSWITH "pl.unstabler.noctiluca"` predicate를 사용하거나
  Console.app에서 timestamp 기준 cross-analysis 합니다.

---

# 10. 에러 매핑

세 가지 에러 도메인이 같은 흐름 안에서 변환됩니다.

```
Navigator (Sirius FileSystemErrorCode)
        ▲
        │ (host app translates)
        │
Host app (Sirius msgdef)
        ▲
        │ (XPC reply: NSError or status code)
        │
Daemon (POSIX errno / NSError)
        ▲
        │ (nanonfs throws NFSError)
        │
NFSv4 client (NFS4ERR_*)
```

데몬 측 매핑 (대표 사례):

| FileSystemErrorCode | nanonfs `NFSError` | NFS4ERR |
|---|---|---|
| `notFound` | `.noEntry` | `NFS4ERR_NOENT` |
| `alreadyExists` | `.exists` | `NFS4ERR_EXIST` |
| `notDirectory` | `.notDirectory` | `NFS4ERR_NOTDIR` |
| `isDirectory` | `.isDirectory` | `NFS4ERR_ISDIR` |
| `notEmpty` | `.notEmpty` | `NFS4ERR_NOTEMPTY` |
| `accessDenied` | `.accessDenied` | `NFS4ERR_ACCESS` |
| `permissionDenied` | `.permission` | `NFS4ERR_PERM` |
| `readOnlyFilesystem` | `.readOnly` | `NFS4ERR_ROFS` |
| `pathTooLong` | `.nameTooLong` | `NFS4ERR_NAMETOOLONG` |
| `invalidPath` | `.invalid` | `NFS4ERR_INVAL` |
| `invalidHandle` | `.badHandle` | `NFS4ERR_BADHANDLE` |
| `staleHandle` | `.stale` | `NFS4ERR_STALE` |
| `notSupported` | `.notSupported` | `NFS4ERR_NOTSUPP` |
| `diskFull` | `.noSpace` | `NFS4ERR_NOSPC` |
| `fileTooLarge` | `.fileTooBig` | `NFS4ERR_FBIG` |
| `quotaExceeded` | `.dirQuota` | `NFS4ERR_DQUOT` |
| `busy` | `.fileBusy` | `NFS4ERR_FILE_OPEN` |
| `ioError` | `.io` | `NFS4ERR_IO` |
| 기타 / 매핑 불가 | `.serverFault` | `NFS4ERR_SERVERFAULT` |

**XPC reply의 NSError 형식**:

- `domain`: `NocFSAccessXPCErrorDomain` (또는 `NSPOSIXErrorDomain` — 구현 시점에 확정).
- `code`: POSIX errno (`ENOENT`, `EACCES`, `ENOTDIR`, ...).
- `userInfo[NSLocalizedDescriptionKey]`: 디버깅용 사람-읽기 메시지 (선택).

호스트 앱이 fsaccess_mount 응답에서 `success=false` + `ErrorInfo(code=...)` 를 받으면
위 표의 `FileSystemErrorCode` → POSIX errno 매핑 (호스트 앱 내부 테이블) 을 거쳐 NSError를
데몬의 XPC reply에 채워 돌려줍니다. 데몬은 errno만 보고 적절한 `NFSError` 를 `throw`
합니다 — `FileSystemErrorCode` enum은 데몬 코드에 존재하지 않습니다. nanonfs가 알아서
NFS4ERR로 wire에 인코딩합니다.

`FileStat.mtimeMs` / `atimeMs` / `btimeMs` 는 ms 단위, nanonfs `NFSTime` 은
sec + nsec 단위입니다. 변환 시 ns 정밀도는 항상 0으로 채웁니다 (lossy).

---

# 11. 보안 / 권한 / Codesigning

- **Sandboxing**: Server.app이 sandboxed인 경우, nocfsaccessd는 같은 sandbox container
  안에서 실행됩니다. `~/NoctilucaFS` 마운트는 NetFS API 경로이므로 sandbox 정책이
  허용해야 합니다 (필요 시 `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-write`
  등 entitlement 검토).
- **Codesigning**: nocfsaccessd는 Server.app과 **동일한 signing identity**로 sign되어야
  합니다. Xcode build phase에서 자동 codesign됩니다.
- **Notarization**: Server.app과 함께 notarize됩니다.
- **방화벽**: `nfs://localhost:<port>/` 는 loopback이므로 macOS Application Firewall에 별도
  허용을 요구하지 않습니다.
- **외부 노출 차단**: `nanonfs` 의 `NFSBind.loopback` 이 외부 IP 바인딩을 precondition으로
  막습니다.

---

# 12. 빌드 / 배포

| 항목 | 값 |
|---|---|
| Xcode target | NoctilucaServer.xcodeproj 안의 Command Line Tool target `nocfsaccessd` |
| Binary 위치 | `Server.app/Contents/MacOS/nocfsaccessd` |
| Spawn 시 조회 | `Bundle.main.url(forAuxiliaryExecutable: "nocfsaccessd")` |
| 의존성 | `NocFSAccessXPC` (shared XPC types), nanonfs (Swift Package), Foundation, OSLog, Network |
| Swift Concurrency | strict |
| 대상 플랫폼 | macOS 14+ (nanonfs와 동일) |
| 라이프사이클 | host app spawn → host app teardown |

> 단독 실행 / 디버그 모드는 두지 않습니다. 환경변수 `NOC_FSACCESSD_XPC_ENDPOINT` 가
> 비어있거나 디코드 실패면 즉시 `exit(EX_USAGE)`.

---

# 13. 테스트 전략

- **데몬 단위 테스트**: nanonfs callback 핸들러 / handle 매핑 테이블 / 가상 트리 갱신 로직은
  XPC mock을 끼워 단위 테스트.
- **통합 테스트**: Server.app + nocfsaccessd 통합 테스트는 host app의 fsaccess 채널
  구현체와 실제 mount_nfs (또는 NetFS API) 마운트를 거쳐 Finder에서 readdir / read /
  write 가 정상 동작하는지 검증.
- **stale cleanup 테스트**: SIGKILL로 host app 강제 종료 후 다음 실행의 startup probe가
  잔재 마운트를 회수하는지 검증.

---

# 14. 향후 / TBD

- **Noctiluca Navigator 측 사용**: 현 단계에서는 Server.app만 spawn. Navigator가 server role을
  가지지 않더라도 (RDP의 `\\tsclient` 와 반대 방향) "원격에서 받은 파일을 로컬에 마운트"
  시나리오에서 동일 데몬을 재사용할 가능성을 열어둠.
- **대용량 read/write 최적화**: 모든 callback이 XPC round-trip이라는 단순함을 우선했지만,
  실제 워크로드에서 throughput이 부족하면 fsaccess의 streaming 경로 + 데몬 측 buffered
  fast path를 추가.
- **NFS handle 영속화**: 현재 데몬은 매 spawn마다 handle을 새로 발급. 호스트 앱과 데몬이
  graceful restart를 원하는 시나리오가 생기면 handle 영속화 검토.
- **macOS Sandbox / App Store 배포**: NetFS API 호출과 helper spawn이 sandbox에서 어떻게
  허용되는지 실측 후 entitlements 정의.

---

# SEE ALSO

- [`fsaccess.mdproto.md`](../SiriusKit/Sources/SiriusKitCore/autogen/msgdef/v1/channels/fsaccess.pb.swift) — fsaccess control channel 메시지 정의
- [`fsaccess_mount.mdproto.md`](../SiriusKit/Sources/SiriusKitCore/autogen/msgdef/v1/channels/fsaccess_mount.pb.swift) — fsaccess_mount data channel 메시지 정의
- [`nanonfs/README.md`](../../nanonfs/README.md) — 사용하는 NFSv4 라이브러리 스펙
