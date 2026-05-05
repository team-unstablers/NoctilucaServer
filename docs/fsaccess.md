# fsaccess (consuming peer)

NoctilucaServer (호스트 앱) 가 fsaccess 의 **consuming peer** 로서 navigator
(NoctilucaClient) 가 노출하는 파일을 호스트 머신의 Finder 에 NFS 마운트로
띄우는 기능.

```
[NoctilucaClient (navigator)]   Sirius   [NoctilucaServer (host app)]   NFSv4   [Finder]
        exposing peer                       consuming peer                     (~/NoctilucaFS)
        fsaccess control 수락               fsaccess control 발신
        fsaccess_mount  수락                fsaccess_mount  발신
        POSIX wrapper / consent UI          NetFS mount + nanonfs listener
                                            가상 트리 + handle table
```

# 설계 결정 (in-process design)

**별도 helper 데몬을 두지 않는다.** ``nanonfs`` 의 NFSv4 listener 는 호스트 앱
(``NoctilucaServer``) 의 같은 process 안에서 실행되며, 호스트 앱이 종료되면
listener 도 함께 정리된다.

> 1차 design (`docs/nocfsaccessd.md`, deleted) 은 별도 데몬 ``nocfsaccessd`` 와
> NSXPCConnection 으로 분리하는 모델이었다. 그러나 ``NSXPCListenerEndpoint`` 의
> mach port 는 ``NSXPCCoder`` 외에서 마샬링되지 않아 환경변수로 자식에 전달할
> 수 없는 게 빌드 후 드러났다. Apple 의 Service Management framework 또는
> launchd 등록 없이는 NSXPC anonymous endpoint 를 host 가 spawn 한 child 에
> 전달할 표준적 방법이 없다 — 우리 시나리오에는 launchd 등록이 부적절했기
> 때문에 in-process design 으로 전환했다.

# 컴포넌트와 책임

본 표는 **host (consuming peer)** 측 책임만 정리합니다. navigator 측 책임 —
노출 entries 등록, consent UX, POSIX wrapper / FileSystemErrorCode 매핑 —
은 NoctilucaClient 의 fsaccess 모듈이 담당하며 본 문서의 범위 밖입니다.

| 책임 | 담당 |
|---|---|
| Sirius `fsaccess` control channel **발신** (List / Mount / Unmount 요청) | host |
| Sirius `fsaccess_mount` data channel **발신** (Open / Read / Write / ReadDir / ...) | host |
| 어떤 entry 를 자동 마운트할지 결정 (defaultConsentPolicy) | host |
| Sirius 인증 + username 추출 | host |
| NFS 서버 운영 (nanonfs `NFSServerListener`, file handle 발급, 가상 트리) | host (in-process) |
| `~/NoctilucaFS` 마운트 / 언마운트 (`NetFSMountURLAsync`, `unmount(MNT_FORCE)`) | host |
| stale mount cleanup (startup probe) | host |

# 가상 트리

```
nfs://localhost:<port>/                     ← NetFS 마운트 root
├── _README.txt                             ← active connection 0 일 때만
├── 0001-cheesekun/                         ← 1단계 connectionLabel (NNNN-username)
│   ├── 내 문서/                             ← 2단계 mount session (sanitized displayName)
│   │   └── ...                              ← navigator 의 실 파일 트리 (XPC X, 직접 호출)
│   └── Blender 작업물/
└── 0002-cheesekun/
```

- 1단계: connection 인증 직후 `NocFSAccessHost.shared.issueConnectionLabel(username:)`
  로 발급된 `NNNN-username`. 호스트 앱 실행 중 monotonic 4-digit zero-padded
  카운터, 재사용하지 않음.
- 2단계: `FileSystemEntry.name` 을 sanitize 한 displayName (`/` / NUL → `_`,
  중복 시 ` (2)`, ` (3)` suffix).
- `_README.txt`: 정적 한국어 + 영어 본문. `VirtualTree.shouldShowReadme()` 가
  active connection 0 개일 때만 true.

# Mount lifecycle

| 이벤트 | 트리거 | 호스트 측 동작 |
|---|---|---|
| Server.app 시작 | `applicationDidFinishLaunching` → `NoctilucaServer.initialize` | `NocFSAccessHost.startupIfEnabled` (settings.fileAccess.enabled 일 때만): mount point probe → `NFSServerListener.run()` (loopback port 0) → `NetFSMountController.mount(port:)` |
| navigator 인증 완료 | `NoctilucaClientSession+Auth` 의 success path | `NocFSAccessHost.issueConnectionLabel` + `addConnection` + `channelManager.openChannel(.fileSystemAccess)` + List 발신 + (defaultConsentPolicy 따라) 자동 Mount loop |
| Mount 응답 success | `NoctilucaClientSession+FSAccess.autoMountEntry` | `NocFSAccessHost.addMountSession` + `channelManager.openChannel(.fileSystemAccessMount, args: [sessionId])` |
| navigator session 종료 | `NoctilucaClientSession.close` | `NocFSAccessHost.removeConnection` (cascade 로 mount session 들 + handle 들 invalidate) |
| Server.app 종료 | `applicationWillTerminate` → `NoctilucaServer.shutdown` | `NocFSAccessHost.shutdownAndUnmount`: `unmount(MNT_FORCE)` → listener cancel |

# NFS callback ↔ fsaccess_mount message 환원

`NoctilucaNFSServer` 가 `NFSServer` 의 21개 callback 을 다음과 같이 처리:

| NFS callback | 처리 |
|---|---|
| `root` | virtual root handle (HandleEntryKind.root) |
| `getattr(root/connection/mountSession)` | virtual directory stat (in-memory) |
| `getattr(_README)` | 정적 stat |
| `getattr(hostFile)` | navigator handle 있으면 `FileSystemFStatRequest`, 없으면 `FileSystemStatRequest(path)` |
| `lookup(root, name)` | "_README.txt" 또는 1단계 connection label 매칭 |
| `lookup(connection, name)` | mountSession displayName 매칭 |
| `lookup(mountSession, name)` / `lookup(hostFile, name)` | path 조립 → `FileSystemStatRequest` → 새 host hostFileId 발급 |
| `readdir(virtualDir)` | virtualTree 스냅샷 |
| `readdir(hostFile)` | `FileSystemOpenRequest(directoryOnly)` → `FileSystemReadDirRequest` |
| `open(parent, name, ...)` | `FileSystemOpenRequest`. 응답 handleId 를 host pathMap 에 attach |
| `close(hostFile)` | `FileSystemCloseRequest` + pathMap unregister |
| `read` | `FileSystemReadRequest` |
| `write` | `FileSystemWriteRequest` |
| `commit` | `FileSystemFlushRequest` |
| `setattr(size)` | `FileSystemFTruncateRequest` |
| `setattr(mode/time)` | best-effort NOOP, 그 후 stat 갱신 |
| `create(directory)` | `FileSystemMkdirRequest` |
| `create(regularFile)` | `FileSystemOpenRequest(createNew)` |
| `remove` | `FileSystemStatRequest` 로 type 판별 → `FileSystemRmdirRequest` 또는 `FileSystemUnlinkRequest` |
| `rename` | `FileSystemRenameRequest` (cross-mountSession 은 `crossDevice`) |
| `readlink` | `FileSystemStatRequest(followSymlinks=false)` 의 `symlinkTarget` |
| `link` | NFSError.notSupported (fsaccess_mount 에 hardlink 가 없음) |
| `lock` / `lockTest` / `unlock` | NFSError.notSupported (NetFS 마운트 옵션 `nolocks` 와 정합) |

# Handle 발급

- `NoctilucaNFSServer` 의 `HandleTable` 이 host-internal entry id (UInt64) 를
  발급. `NFSFileHandle.bytes` 는 그 entry id 를 8-byte big-endian 으로 인코딩.
- `HandleEntry` 종류: `root`, `readme`, `connection`, `mountSession`, `hostFile`.
- `hostFile` entry 는 `FSAccessMountChannel.MountSessionPathMap` 의
  host-side handleId 를 가리킴 (path / navigator handle 매핑).
- mount session 제거 시 `HandleTable.invalidateAll(mountSession:)` 가 cascade
  로 invalidate. 이후 그 NFSFileHandle 은 NFSError.stale 응답.

# 보안 / 권한

- **loopback 한정**: `NFSBind.loopback(port: 0)` + `kNetFSAllowLoopbackKey`.
  외부 인터페이스 바인딩 의도적으로 안 함.
- **사용자 권한**: NetFS API 가 user-level mount 지원 — setuid root helper 또는
  `vfs.usermount` 변경 불필요.
- **방화벽**: loopback 이므로 macOS Application Firewall 허용 요구 없음.
- **AUTH_SYS only**: nanonfs 기본. loopback 가정 하 추가 인증 없음.

# 미완성 / 향후

- **NFSv4 LOCK / LOCKT / LOCKU**: 현재는 fake success (advisory lock 잡힌
  *척*) 로 응답한다. QuickTime 같은 client 가 read 전 LOCK 시도하는데 NOTSUPP
  주면 read 자체를 시작 안 해서 어쩔 수 없는 우회. 진짜 lock 무결성을 위해서는
  `fsaccess_mount` mdproto 에 `FileSystemLockRequest/Response` /
  `FileSystemUnlockRequest/Response` opcode 를 신설하고 navigator 측에서
  `fcntl(F_SETLK)` / `flock(2)` 로 실제 fd lock 을 잡아야 한다. 별도 PR.
- streaming read/write (`FileSystemRequestStreamRead` /
  `FileSystemRequestStreamWrite`) 미구현. 현재는 단순 chunked read/write 만.
- `ServerNoticeCode.quotaExceeded` 신설 (Pattern A hard threshold escalation
  용). 현재는 `protocolViolation` 으로 fallback.
- consent policy `alwaysAsk` 의 macOS 알림 UI 구현 (현재는 단순 skip).
- AppStream 같이 multi-instance navigator (한 호스트 + 여러 navigator) 에서
  connectionLabel collision 검증.

# SEE ALSO

- `NoctilucaServer/feature/fsaccess/AGENTS.md` — 모듈 코드 구조
- `SiriusKit/.../fsaccess.mdproto.md` — control channel 메시지 정의
- `SiriusKit/.../fsaccess_mount.mdproto.md` — data channel 메시지 정의
- `../../nanonfs/README.md` — NFSv4 라이브러리
