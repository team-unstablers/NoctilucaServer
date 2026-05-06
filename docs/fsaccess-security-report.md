# fsaccess 보안 감사 보고서

| 항목 | 내용 |
| --- | --- |
| 작성일 | 2026-05-06 |
| 대상 타겟 | NoctilucaServer (Swift / macOS), NoctilucaClient (Swift / macOS·iOS) |
| 대상 feature | `SiriusFeature.fileSystemAccess`, `SiriusFeature.fileSystemAccessMount` |
| 대상 프로토콜 | SiriusKit msgdef `msgdef/v1/channels/fsaccess.proto`, `msgdef/v1/channels/fsaccess_mount.proto` |
| 커밋 기준 | `fsaccess` 브랜치 (`appstream-swift6..fsaccess`, 39 커밋) |
| 리뷰 앵글 | 보안 경계 + 신뢰 모델 |

본 문서는 fsaccess feature — host (NoctilucaServer) 가 consuming peer 로서
navigator (NoctilucaClient) 가 노출하는 파일을 호스트 머신의 Finder 에 NFS
마운트로 띄우는 기능 — 의 신뢰 모델 / 보안 경계를 검토한 결과입니다. 깊이는
**선택한 앵글 한정으로 깊게**, 폭은 path 게이트 + consent flow + NFS listener +
cross-session isolation 을 모두 다룹니다. 동시성/NFS 정확성/error mapping 각도는
본 리뷰의 범위 밖입니다 (다음 라운드 후보).

각 발견은 **① 위치 → ② 시나리오 → ③ 영향 → ④ 권장 조치** 형태로 정리했습니다.

---

## 0. TL;DR (요약)

- **CRITICAL (C1)**: navigator 측 `FSAccessPathValidator.resolve()` 가 순수 lexical
  검증만 수행하고, `mountRoot` 도 `standardizedFileURL` 까지만 정규화함. `handleOpen`
  / `handleMkdir` / `handleRmdir` / `handleUnlink` / `handleRename` /
  `handleStat(followSymlinks=false)` 가 **open / stat 이후 `isWithin` 사후검증을
  하지 않음**. mount subtree 안의 *중간 component* 가 symlink 면 `open(2)` 가
  그것을 follow 해 mount root 밖 파일의 fd 를 잡아 read 응답으로 흘려보낼 수 있음.
  **macOS only** (iOS 는 sandbox 가 follow 차단).
- **CRITICAL (C2)**: NFS listener 가 `127.0.0.1:25440` 으로 *hardcoded* loopback
  바인딩 + AUTH_SYS only + UID 클라이언트 자체 클레임 (nanonfs). 같은 사용자의
  *다른 프로세스* (network.client entitlement 보유한 일반 sandboxed 앱 포함) 가
  포트로 직접 NFSv4 connect → 임의 UID 클레임 → 모든 활성 mount session 의
  entry 를 read/write 가능. 신뢰모델이 "같은 사용자의 같은 프로세스" 까지로
  좁아져야 하는데 docs 의 "loopback 가정 하 추가 인증 없음" 은 *프로세스 경계*
  를 고려하지 않음. 추가로 docs/AGENTS 가 `port 0` (OS-할당) 이라고 적은 것과
  코드 (`25440` hardcode) 가 불일치.
- **CRITICAL (C3)**: `mount_nfs` options 에 `docs/fsaccess.md` 가 약속한 `nolocks`
  가 없음. doc-vs-code 불일치 (보안 자체 영향은 없으나 fake-lock 정책의 *근거*
  를 docs 가 잘못 설명).
- **HIGH (H1)**: `bootstrapFSAccessMounts` 가 navigator 의 list 응답 entry 를
  *무조건 자동 마운트*. host 사용자가 어떤 entry 가 올라왔는지 확인하거나
  거절할 UI 가 없고, host 측 안전장치는 `alwaysReadOnly` 토글 하나뿐.
  단일유저 데스크톱 모델 (memory) 결정과 일관되어 의도된 설계지만, multi-user
  / 공유 워크스테이션에서는 부적절 — docs 에 명시 필요.
- **HIGH (H2)**: `VirtualTree.sanitizedAndDeduped` 가 `/` 와 `\u{0000}` 만 치환.
  control chars (`\n`, `\r`, `\t`), leading `.`, literal `..`, shell metachar
  (`;`, `$`, backtick) 통과.
- **MEDIUM (M1)**: `handleStat(followSymlinks=true)` 가 stat 호출 *후* `isWithin`
  검사 → mount root 밖 파일의 존재 여부 oracle (ENOENT vs policyViolation 으로
  구분) + atime side-effect.
- **MEDIUM (M2)**: `handleOpen` 의 `accessMode=.read` + `createDisposition=.createNew`
  조합이 허용 → `O_RDONLY|O_CREAT|O_EXCL` (빈 read-only 파일 생성). spec 의 의도된
  동작인지 명시 필요.
- **MEDIUM (M3)**: `FSAccessChannel.sendMountFailure` 가 success=false 응답에
  `sessionId=UUID()`, `grantedAccess=.read`, `supportsLocks=false` 의 가짜 값
  주입. mdproto 가 "success=false 시 ignore" 명시 안 되어 있으면 사고 가능성.
- **MEDIUM (M4)**: `handleClose` 의 implicit fsync 실패 시 fd 는 이미 닫혀
  있는데 success=false 반환 → 호출자가 retry 못 함.
- **LOW**: `HandleTable.nextId` wrap-around (`UInt64` overflow → 16 으로 리셋)
  은 비현실적. `NocFSAccessHost.startListener` timeout=5s 가 짧을 수 있음.
  bootstrap 의 entry 직렬 mount 가 UX 측면에서 느림.

아래에서 각 항목을 자세히 다룹니다.

---

## 1. 대상 및 신뢰 모델

### 1.1 컴포넌트 범위

| 타겟 | fsaccess control 경로 | fsaccess_mount 경로 |
| --- | --- | --- |
| NoctilucaServer (host) | `NoctilucaServer/feature/fsaccess/FSAccessChannel.swift`, `FSAccessConsumingState.swift`, `FSAccessRequestRouter.swift`, `client-session/NoctilucaClientSession+FSAccess.swift` | `NoctilucaServer/feature/fsaccess/FSAccessMountChannel.swift` |
| NoctilucaClient (navigator) | `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessChannel.swift`, `FSAccessConsentBroker.swift`, `core/state/RemoteSession.swift` | `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessMountChannel.swift`, `FSAccessPathValidator.swift`, `FSAccessHandle.swift`, `FSAccessIOSDocumentsProvider.swift` |
| NFS server (host in-process) | `NoctilucaServer/feature/fsaccess/nfs/NoctilucaNFSServer.swift`, `nfs/HandleTable.swift`, `nfs/VirtualTree.swift`, `daemon/NocFSAccessHost.swift`, `daemon/NetFSMountController.swift`, `daemon/MountPointSupervisor.swift`, `daemon/FSAccessSignalGuard.swift` |
| nanonfs (외부 라이브러리) | `nanonfs/Sources/NanoNFS/Wire/RPCSession.swift`, `Public/NFSBind.swift` |

### 1.2 신뢰 모델

```
[host = consuming peer]                        [navigator = exposing peer]
                                                    │
              entry list                            │ ◄─── 사용자 = 신뢰 source
              consent broker                        │
              path validation         (← 게이트)    │
              symlink containment ✗ (C1)            │
                                                    ▼
   NFS listener
   ↑ loopback 25440 hardcode (C2)
   ↑ AUTH_SYS UID self-claim (C2)
   ↑ 같은 사용자의 다른 프로세스 진입 가능 (C2)

   bootstrapFSAccessMounts: navigator 결정 100% 신뢰 (H1)
```

설계상의 신뢰 가정:

- navigator 측 사용자 (= 같은 인간) 가 어떤 entry 를 노출할지 직접 결정한다.
- navigator 의 PathValidator 와 ConsentBroker 가 사실상 유일한 의미 있는 게이트다.
- host 의 Sirius 인증 이후에는, host 는 그 인증된 navigator 를 데이터 소유자로 신뢰한다.
- host 머신은 단일 사용자 데스크톱이며, 다른 사용자의 셸/에이전트가 동시에 활동하지 않는다 (project memory 의 "단일 프로세스 / 단일 유저 데스크톱 모델" 결정).

이번 리뷰가 위반을 발견한 가정:

- **navigator 의 PathValidator 가 mount root 안에 들어온 *모든* path 가 mount root 안에 머문다고 보장한다** — *실제로는 lexical 검증만 하므로 symlink 가 끼면 깨짐* (C1).
- **NFS listener 는 같은 머신의 같은 사용자만 reach 한다** — *실제로는 같은 사용자의 임의 프로세스가 reach 가능* (C2).

---

## 2. 발견사항

### C1. symlink 가 사이에 끼면 mount root 밖으로 나간다 (macOS only)

**위치**:
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessPathValidator.swift:66` (`resolve()`)
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessChannel.swift:237` (`rootURL: URL(fileURLWithPath: entry.path).standardizedFileURL`)
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessMountChannel.swift` 의 `handleOpen` (라인 221), `handleMkdir` (634), `handleRmdir` (666), `handleUnlink` (699), `handleRename` (730), `handleStat` (494) (followSymlinks=false 분기)

**시나리오**:

1. navigator 측 사용자가 `~/Public` 을 entry 로 노출.
2. 해당 폴더 안에 누군가 (또는 사용자 본인의 실수) `~/Public/escape -> /Users/cheesekun` symlink 를 둠.
3. host (consuming peer) 의 NFS 마운트에서 Finder 가 `escape/.ssh/id_rsa` 를 lookup
   하면 NFS server 가 navigator 에게 `FileSystemStatRequest("escape/.ssh/id_rsa", followSymlinks=false)` 발신.
4. `FSAccessPathValidator.resolve()` 는 lexical 검증만 하므로 통과
   (`escape`, `.ssh`, `id_rsa` 셋 다 일반 component).
5. 이후 host NFS server 가 read 등을 위해 `FileSystemOpenRequest("escape/.ssh/id_rsa", flags: [])`
   를 보내면, navigator 의 `handleOpen` 은 `noc_open_with_mode` 호출 시
   `O_NOFOLLOW` 를 set 하지 않고 (호출자가 명시 요청한 경우만 set), 더더욱
   `O_NOFOLLOW_ANY` 같은 *모든 component* 차단 플래그도 없음.
6. `open(2)` 가 모든 component 를 follow → `/Users/cheesekun/.ssh/id_rsa` 의 fd
   가 잡힘 → 후속 `FileSystemReadRequest` 응답에 SSH 개인키 내용이 흘러나옴.

`FSAccessPathValidator.isWithin(_:root:)` 는 정의는 있지만 (symlink resolve 후
prefix check), **`handleStat(followSymlinks=true)` 분기에서만 호출** (라인 526-532).
다른 path-based op 에는 사후검증이 없음.

**영향**:

- mount root 밖 파일의 read/write/unlink/rename 가능.
- 정보 노출 (path 존재 / 메타데이터 / 내용).
- mutating op (mkdir, rename, unlink) 까지 가능 — 데이터 무결성도 침해.

**iOS 영향 없음**: iOS App Sandbox 가 컨테이너 밖 symlink follow 를 차단하므로
이 경로로는 escape 불가능. macOS-only 이슈.

**권장 조치**:

1. **추천**: `noc_open_with_mode` 호출 시 `O_NOFOLLOW_ANY` (macOS 11+) 를 default 로 OR 적용.
   동일하게 `noc_stat` 도 `lstat` + symlink 처리 전에 component-by-component
   검증 또는 `O_NOFOLLOW_ANY` 를 받는 `openat` + `fstatat` 패턴으로 재구성.
2. **차선**: 모든 path-based op 의 진입점에 다음 패턴 도입:
   - `FSAccessPathValidator.resolve(...)` 로 lexical normalize.
   - `realpath(resolvedURL)` 또는 `fcntl(fd, F_GETPATH, ...)` 로 실 경로 획득.
   - `realpath(mountRoot)` prefix 검증 → 실패 시 해당 fd close + `.policyViolation` 반환.
3. `mountRoot` 자체도 `URL.standardizedFileURL.resolvingSymlinksInPath()` 로
   생성해 비교 기준점이 일관되도록.
4. `FSAccessPathValidator` 의 docstring 이 "(호출자가 심볼릭 링크 follow 한
   경우) subtree 재검사" 라고 적은 부분과, 실제로 호출하지 않는 핸들러들의
   불일치를 정정.

---

### C2. NFS listener 가 hardcoded loopback port + AUTH_SYS UID self-claim

**위치**:
- `NoctilucaServer/feature/fsaccess/daemon/NocFSAccessHost.swift:161` (`bind: .loopback(port: 25440)`)
- `nanonfs/Sources/NanoNFS/Public/NFSBind.swift:24` (loopback 의 default 가 `127.0.0.1`)
- `nanonfs/Sources/NanoNFS/Wire/RPCSession.swift:50-58` (AUTH_SYS only, UID self-claim)
- `nanonfs/Sources/NanoNFS/RPC/RPCMessage.swift:112-` (AUTH_SYS body parser, UID/GID 클라이언트가 보낸 그대로 사용)

**시나리오**:

1. host 가 fsaccess 를 활성화하면 in-process NFS listener 가 `127.0.0.1:25440` 으로 listen.
2. 같은 Mac 의 *다른 프로세스* (예: network.client entitlement 만 있는 일반
   사용자 앱; sandbox 든 비-sandbox 든) 가 `127.0.0.1:25440` 으로 직접 TCP connect.
3. RPC 핸드셰이크에서 AUTH_SYS credential body 의 UID/GID 를 임의 값으로 클레임.
4. nanonfs 는 이를 검증 없이 수락 (`RPCSession.swift:50-` 의 "AUTH_SYS only" 분기).
5. 공격자가 root file handle (`HandleTable.encode(rootEntryId)` = 8-byte big-endian UInt64,
   값 = 1) 을 직접 구성해 readdir/lookup → 모든 connection / mount session /
   host file 트리를 navigation.
6. 활성 mount session 의 entry 들을 read/write.

**영향**:

- 신뢰 모델이 "같은 사용자의 같은 프로세스" 까지 좁아져야 하는데 현재 코드는
  "같은 사용자의 임의 프로세스" 까지 열려있음. **로컬 권한 우회**.
- 이는 단일유저 데스크톱 모델 가정과도 무관. 같은 인간이 띄운 다른 앱이
  파일 노출 entry 를 모두 읽는 것은 사용자 의도가 아님.
- docs 의 *프로세스 경계 미고려* 가 표면화된 결과.

**부수 발견 — doc-vs-code 불일치**:

- `docs/fsaccess.md:70` 와 `NoctilucaServer/feature/fsaccess/AGENTS.md` (해당
  부분 대응 위치) 는 listener 를 "loopback port 0" (OS-할당) 으로 설명.
- 실제 코드 (`NocFSAccessHost.swift:161`) 는 `25440` hardcode.
- docs 가 약속한 동작이 더 안전 (port enumeration race window 좁음).

**권장 조치 (impact 순)**:

1. **즉시 적용 가능**: `bind: .loopback(port: 0)` 으로 변경 → OS 할당 ephemeral port.
   - 현재 코드에서 `boundAddress.port` 를 polling 으로 받는 흐름이 이미 있어서 (라인 178-186),
     port 0 으로 풀어도 곧바로 `mount_nfs` 인자에 동적 port 를 넘기는 게 가능.
   - docs 와 코드 동시 정합.
2. **추가 방어**: short-lived random token 을 mount session 의 NFSv4 path 에 박아두기.
   예: `nfs://localhost:port/<token>` 으로 마운트. listener 가 token 안 맞는
   요청은 root 부터 거절. token 은 mount 시점에 생성 → URL 로 `mount_nfs` 에만 전달 →
   외부 프로세스가 추측 불가.
3. **장기**: nanonfs 에 process credential 검증 hook 추가 (peer pid 의 uid 확인).
   socket level peer credential (SO_PEERCRED on Linux, `getpeereid` 비슷한 macOS API)
   는 TCP loopback 에서는 직접 안 되지만, 연결 직후 `SO_NOSIGPIPE` + `getsockopt`
   조합으로 우회 가능. 추가 조사 필요.
4. AUTH_SYS UID 자체는 "advisory" 임을 docs 에 명시. 즉 nanonfs 는 spoof 가능
   하다는 점을 설계 전제로 못박고, 다른 layer (port 추측 불가 / token / pf 룰)
   에서 막는다는 것을 분명히.

---

### C3. mount_nfs options 에 nolocks 가 없음 — docs 와 코드 불일치

**위치**:
- `NoctilucaServer/feature/fsaccess/daemon/NetFSMountController.swift:41`
- `docs/fsaccess.md:104`

**시나리오**:

`docs/fsaccess.md` §"NFS callback ↔ fsaccess_mount message 환원" 표는 lock /
lockTest / unlock 의 처리를 "NFSError.notSupported (NetFS 마운트 옵션 `nolocks`
와 정합)" 으로 설명. 그러나 실제 `NetFSMountController.mount` 의 options
문자열은:

```
"vers=4,port=\(port),mountport=\(port),tcp,rsize=1048576,wsize=1048576,dsize=1048576"
```

`nolocks` 가 없음. 결과적으로:

- NFS client (Finder / QuickTime 등) 가 LOCK / LOCKT / LOCKU callback 을 정상적으로 시도.
- nanonfs / `NoctilucaNFSServer.lock(...)` 가 이를 받아서 *그제서야* `useFakeLocks`
  설정 또는 `supportsLocks` capability 분기로 처리.
- 즉 fake-lock 정책이 작동하는 *이유* 자체가 docs 가 설명한 것과 다름.

**영향**:

- 보안 자체 영향은 없음 (현재 분기 로직이 결과적으로 동일한 동작을 만듦).
- 그러나 docs 가 잘못된 설명을 제공 → 미래의 유지보수자가 "이건 nolocks
  덕분이니까 코드를 바꿔도 된다" 라고 오판할 위험.

**권장 조치**:

1. 둘 중 하나로 일관화:
   - **(추천)** docs 를 정정. lock callback 이 *실제로 들어오며* host 측 분기
     로직이 fake / wire dispatch 를 결정한다는 흐름을 정확히 기술.
   - 또는 코드를 정정. 진짜로 `nolocks` 를 mount option 에 넣고 `useFakeLocks`
     설정과 wire dispatch 분기를 단순화.
2. 후자를 택할 경우 byte-range lock wire dispatch (방금 구현한 PR 의 핵심
   기능) 가 **실제로 NFS client 로부터 LOCK callback 을 받지 못하게 됨** —
   기능 회귀. 따라서 docs 정정이 합리적.

---

### H1. 호스트는 navigator 의 list 응답 entry 를 무조건 자동 마운트

**위치**:
- `NoctilucaServer/client-session/NoctilucaClientSession+FSAccess.swift:81-107` (`bootstrapFSAccessMounts`)
- `NoctilucaServer/client-session/NoctilucaClientSession+FSAccess.swift:109-167` (`autoMountEntry`)

**시나리오**:

Sirius 인증 완료 직후 host 가:

1. fsaccess control channel open.
2. `requestList()` 발신 → navigator 가 노출 entry 목록 반환.
3. **모든 entry 를 자동 mount** (`for entry in listResponse.entries { autoMountEntry(...) }`).
4. mount 성공한 각 entry 마다 fsaccess_mount channel 도 자동 open.

host 사용자 (= 호스트 머신 앞의 인간) 가 어떤 entry 가 올라왔는지 확인하거나
거절할 UI 가 없음. host 측 안전장치는 `AppSettings.fileAccess.alwaysReadOnly`
토글 하나뿐.

**영향**:

- project memory 의 "단일 프로세스 / 단일 유저 데스크톱 모델" 결정과 일관 →
  **의도된 설계**.
- 그러나 *다른 모델* (multi-user 워크스테이션, 공유 SSH/터미널 환경, 회사
  공용 Mac 등) 에서는 부적절. 다른 사용자가 navigator 와 짝지은 시나리오에서
  제3자 host 사용자가 그 사실을 모른 채 마운트만 받음.

**권장 조치**:

1. docs 와 AGENTS.md 에 "host 측 합의 = `alwaysReadOnly` 단일 토글" 임을 명시.
2. 향후 multi-user 시나리오를 도입할 거면 host 측에도 mini-broker (메뉴바
   알림 등) 도입 검토. 단 docs/AGENTS 의 "단일유저" 결정 자체는 존중.
3. 자동 mount 결과를 host 측 UI (메뉴바 / Settings) 에 visible 하게 — "어떤
   entry 가 마운트되었는가" 를 사용자가 즉시 파악할 수 있게.

---

### H2. VirtualTree displayName sanitize 가 좁다

**위치**:
- `NoctilucaServer/feature/fsaccess/nfs/VirtualTree.swift:127-143`

**시나리오**:

```swift
sanitized = sanitized.replacingOccurrences(of: "/", with: "_")
sanitized = sanitized.replacingOccurrences(of: "\u{0000}", with: "_")
```

`/` 와 NUL 만 치환. 통과되는 이름:

- control chars: `\n`, `\r`, `\t`, ESC, BEL — Finder 표시 시 깨짐 / 터미널에서
  copy-paste 할 때 이상한 동작.
- leading `.`: `.hidden` — Finder 가 숨김 처리.
- literal `..`: NFS LOOKUP 의 `..` (parent navigation) semantics 와 충돌.
  가상 트리 디렉토리이므로 실제 path escape 는 없지만 NFSv4 client 가
  `..` 를 child name 으로 보내는 일은 거의 없어 운영상 안전.
- shell metachar (`;`, `$`, backtick): 현재 host 에서 이 path 가 shell 로
  흘러들어갈 경로는 없으나 미래 surface.

**영향**:

- 보안 영향 낮음 — navigator 의 entry name 은 같은 사용자가 자기 client UI
  에서 직접 입력한 값.
- UX 영향 medium — Finder 표시가 깨지거나 사용자가 터미널 navigation 시 quoting
  실수 유발.

**권장 조치**:

1. sanitize 규칙 강화:
   - control chars (`\u{0001}-\u{001F}`, `\u{007F}`) 를 `_` 로 치환.
   - leading `.` 은 `_` prefix 로 escape (예: `.foo` → `_foo`).
   - 정확히 `.` 또는 `..` 면 `(unnamed)` 로 대체.
2. 단순한 문자열 sanitize 대신 NFKC normalize → restricted Unicode set 도 고려
   가능 (over-engineering 일 수 있음).

---

### M1. handleStat(followSymlinks=true) 가 stat 호출 *후* isWithin 검사 → 존재 여부 oracle

**위치**:
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessMountChannel.swift:494-543` (`handleStat`)

**시나리오**:

```swift
let resolvedURL = try FSAccessPathValidator.resolve(...)  // lexical only
// ...
if request.followSymlinks {
    result = noc_stat(cstr!, &statStruct)   // mount root 밖의 파일도 stat 됨
} else {
    result = noc_lstat(cstr!, &statStruct)
}
if result != 0 {
    sendError(... mapErrno ...)             // ENOENT → "그 path 는 없음"
    return
}
if request.followSymlinks {
    if !FSAccessPathValidator.isWithin(...) {
        sendError(... .policyViolation ...) // "있긴 있지만 mount 밖"
        return
    }
}
```

호출자 (host NFS server) 입장에서 두 응답을 구분 가능:

- ENOENT/EACCES 등 errno → "그 path 가 없거나 접근 권한 없음".
- policyViolation → "그 path 는 존재하며 mount root 밖이다".

→ navigator 측 사용자 home 디렉토리의 임의 절대경로 존재 여부를 확인 가능
(symlink trick 으로 절대경로 prefix 를 mount 안에 박아넣기만 하면 됨).

**영향**:

- 파일 *내용* 은 leak 안 되지만 path enumeration / 메타데이터 oracle.
- atime 갱신 같은 부수효과 발생 (관찰자 효과).

**권장 조치**:

1. C1 의 권장 조치와 통합. realpath check 를 stat *전* 에 수행:
   - `resolve()` 직후 `realpath(resolvedURL)` 시도.
   - mountRoot prefix 안에 안 들어오면 stat 호출 없이 즉시 `.policyViolation` (혹은 `.invalidPath`).
2. 또는 `fstatat(AT_FDCWD, resolvedURL, ..., AT_SYMLINK_NOFOLLOW)` 후
   대상이 symlink 면 readlink + isWithin 으로 사전 차단.

---

### M2. handleOpen 의 read + createNew 조합 허용

**위치**:
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessMountChannel.swift:303-329`

**시나리오**:

```swift
switch request.accessMode {
case .read: openFlags |= O_RDONLY
// ...
}
switch request.createDisposition {
case .createNew: openFlags |= O_CREAT | O_EXCL
// ...
}
```

`accessMode=.read` + `createDisposition=.createNew` → `O_RDONLY|O_CREAT|O_EXCL`.
POSIX 상 valid (빈 read-only file 만듦). mdproto 의 의도된 의미인지 spec 에
명시되어 있지 않음.

**영향**:

- 보안 영향 낮음 — 어차피 read access 만 있는 핸들이므로 데이터 leak/주입 경로 없음.
- semantic 모호성. 호출자가 의도한 동작인지 spec 으로부터 추론하기 어려움.

**권장 조치**:

1. `fsaccess_mount.mdproto.md` 의 OPEN 섹션에 `accessMode` × `createDisposition`
   매트릭스를 명시.
2. 어색한 조합 (read + createNew, write + truncateExisting + read 등) 은 either:
   - 명시적으로 허용 + 의도 설명.
   - 명시적으로 거절 (`.invalidArgument`).

---

### M3. sendMountFailure 가 가짜 sessionId / supportsLocks=false 로 응답

**위치**:
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessChannel.swift:257-266`

**시나리오**:

```swift
private func sendMountFailure(...) async throws {
    try await handle.send(opcode: .fileSystemMountResponse, message: FileSystemMountResponse(
        requestId: requestId,
        success: false,
        sessionId: UUID(),                // ← 가짜
        grantedAccess: .read,             // ← 가짜
        error: ...,
        supportsLocks: false              // ← 가짜
    ))
}
```

Mount 실패 응답에서 sessionId / grantedAccess / supportsLocks 필드는 의미가 없는
값이지만 wire 에 그대로 전송됨.

**영향**:

- mdproto 가 "success=false 시 these fields are ignored" 를 명시하면 ✓.
- 명시 안 되어 있으면, 호스트 측이 실수로 가짜 sessionId 를 router 에 등록하는
  버그가 생길 수 있음. 현재 host 코드 (`autoMountEntry`) 는 `mountResponse.success`
  먼저 체크하므로 즉각적인 영향은 없음.

**권장 조치**:

1. mdproto 의 `FileSystemMountResponse` 섹션에 "success=false 일 때 sessionId
   / grantedAccess / supportsLocks 는 무시된다" 를 명시 추가.
2. 또는 protobuf 메시지 정의에서 success / failure 를 oneof 로 갈라서 wire
   레벨에서 강제. (현재 PR scope 밖.)

---

### M4. handleClose 의 fsync 실패 시 fd 가 이미 닫혔는데 success=false

**위치**:
- `NoctilucaClient/NoctilucaClient/core/feature/fsaccess/FSAccessMountChannel.swift:367-381`

**시나리오**:

```swift
var flushError: ErrorInfo? = nil
if case .file(let fd) = h.kind, h.accessMode != .read {
    if Darwin.fsync(fd) != 0 {
        flushError = FSAccessErrorMapper.errorInfoFromErrno(message: "fsync during close failed")
    }
}
h.closeIfNeeded()                          // ← fd 닫음
try await handle.send(... success: flushError == nil, error: flushError ...)
```

fsync 가 실패해도 close 는 진행되고 success=false 응답이 감. 호출자는 동일
fd 로 retry 못 함 (이미 사라짐).

**영향**:

- 데이터 손실의 *알림* 은 됨 (호출자가 ENOSPC / EIO 같은 errno 받음).
- 그러나 retry 하려면 다시 OPEN → write → close 해야 하는데 그 사이 race 가능.
- POSIX 자체가 "fsync 실패 후 close" 의 retry semantics 를 잘 정의 안 함.

**권장 조치**:

1. 현재 동작이 mdproto 에서 명시되어 있으면 ✓.
2. 더 안전한 동작은:
   - close 전에 별도 explicit `flush` 메시지를 받아 호출자가 retry-able 하게.
   - 또는 close 응답에서 fsync 가 실패하면 fd 를 *닫지 않고* error 만 반환.
     호출자가 다시 close 또는 explicit flush 호출 후 close. 이 경우 핸들
     leak 회피를 위해 timeout 보강 필수.

---

### Low

- **HandleTable.nextId wrap-around** (`NoctilucaServer/feature/fsaccess/nfs/HandleTable.swift:55-57`):
  `nextId` 가 `UInt64` overflow 후 0 이 되면 16 으로 점프. 비현실적
  (2^64-16 entry 가 발급되어야 함).
- **NocFSAccessHost.startListener timeout 5s** (`daemon/NocFSAccessHost.swift:177-186`):
  Apple Silicon Rosetta translation 환경 등 부팅 race 에서 가끔 짧을 수 있음.
  사고 보고 기준 데이터 없음.
- **bootstrapFSAccessMounts 의 entry 직렬 mount** (`client-session/NoctilucaClientSession+FSAccess.swift:99-107`):
  32개 entry 를 순차 mount 하면 전체 latency 가 32×roundtrip. UX 영향만 있음.
- **FSAccessHandle 의 deinit-only resource cleanup**: lock + `_kind = nil`
  로 race 안전. ✓ 문제 없음.

---

## 3. 우선순위 권장

| 순위 | 항목 | 난이도 | 효과 |
|---|---|---|---|
| 1 | C1 (`O_NOFOLLOW_ANY` default 적용) | 낮음 | 매우 큼 (path traversal 완화) |
| 2 | C2 (loopback port 0 으로) | 낮음 | 큼 (process boundary 강화) |
| 3 | C3 / H1 / M1 (docs / AGENTS 정정) | 매우 낮음 | 중간 (오해 방지) |
| 4 | C2 추가 방어 (token-in-path) | 중간 | 큼 (port enumeration 봉쇄) |
| 5 | H2 (sanitize 강화) | 낮음 | 작음 |
| 6 | M2 / M3 (mdproto 명시) | 낮음 | 작음 |
| 7 | M4 (fsync semantics 재검토) | 중간 | 작음 |

C1 과 C2 둘 다 코드 변경량이 작고 즉시 적용 가능.

---

## 4. 본 리뷰의 범위 밖 (다음 라운드 후보)

본 리뷰는 보안 경계 + 신뢰 모델 각도에 집중했습니다. 다음 영역은 *깊이* 검토
하지 않았으며, 별도 라운드에서 다루기를 권장합니다:

- **동시성 / actor 격리**: `FSAccessRequestRouter`, `NoctilucaNFSServer`,
  `MountSessionPathMap`, `HandleTable` 의 actor 경계와 race. 특히 동시 OPEN
  이 같은 path 에 대해 hostFileId 를 다르게 발급할 가능성, `attachNavigatorHandle`
  의 race window. Swift 6 strict concurrency 호환.
- **NFSv4 정확성 + 리소스 lifecycle**: fileid/mtime 안정성, stale handle
  semantics, readdir cookie/eof, mount session cascade invalidation, NetFS
  mount/umount 회복 경로, signal guard 의 시그널 핸들러 안전성.
- **에러 처리 + spec violation 매트릭스**: `FSAccessErrorMapper` 의 errno
  매핑 정확성, `FileSystemErrorCode` ↔ `NFSError` 환원의 lossy 여부,
  channel close 임계값 (Pattern A) 가 실제 구현과 정합한지 (`AGENTS.md`
  spec violation 매트릭스 검증).
- **Cross-feature 영향**: AppStream / projection 과 fsaccess 가 같은 host 의
  단일 사용자 가정을 깨는 시점 (예: AppStream 으로 다른 navigator 가 동시
  접속 시 connectionLabel collision).

---

## SEE ALSO

- `docs/fsaccess.md` — fsaccess feature 의 설계 문서 (정본).
- `NoctilucaServer/feature/fsaccess/AGENTS.md` — 서버 측 모듈 코드 구조.
- `docs/clipboard-transfer-security-report.md` — 같은 컨벤션으로 작성된
  ClipboardChannel / TransferChannel 보안 감사 (참고).
- `docs/spec-violation-policy.md` — 본 리뷰가 인용하는 Pattern A 분류 규정.
