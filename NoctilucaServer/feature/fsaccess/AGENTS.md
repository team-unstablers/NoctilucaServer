# fsaccess (consuming peer)

서버(NoctilucaServer = host)가 **consuming peer** 로서 fsaccess control / fsaccess_mount
channel 을 발신하고, 받은 응답을 ``nocfsaccessd`` 데몬에 reverse-XPC 로 forward 하는
모듈. navigator (NoctilucaClient) 가 노출하는 파일을 호스트 머신의 Finder 에 NFS
마운트로 띄우는 것이 목표.

상위 설계는 `docs/nocfsaccessd.md` 가 정본입니다.

# Files

- `FSAccessChannel.swift` — control channel (`handle.direction == .local`).
  List / Mount / Unmount 요청 발신. `requestList` / `requestMount` /
  `requestUnmount` 의 typed continuation 으로 응답 매칭.
- `FSAccessMountChannel.swift` — data channel. mount session 별 1 인스턴스.
  13개 fsaccess_mount message 발신 + `FSAccessMountReply` enum 으로 응답 unification.
  내부에 `MountSessionPathMap` (host-side handleId → path / navigator handle 매핑) 보관.
- `FSAccessConsumingState.swift` — control channel 의 inner state. List 응답 entries,
  mount session record, requestId 발급기.
- `FSAccessRequestRouter.swift` — process-wide actor. mountSessionId → 활성
  ``FSAccessMountChannel`` 매핑. ``NocFSAccessHostXPCExport`` 의 reverse-XPC
  콜백 dispatch 시 사용.
- `FSAccessErrorTranslator.swift` — Sirius `FileSystemErrorCode` → Darwin errno →
  `NSError(domain: NSPOSIXErrorDomain, code: errno)` 매핑.
- `FSAccessChannelStartArgs.swift` — fsaccess_mount channel start args[0] 의 sessionId
  UUID 직렬화.
- `daemon/NocFSAccessDaemonHost.swift` — `nocfsaccessd` 자식 프로세스 supervisor.
  NSXPCListener.anonymous + spawn + `daemonReady` waitup + graceful shutdown
  + ~/NoctilucaFS NetFS 마운트.
- `daemon/NocFSAccessHostXPCExport.swift` — `NocFSAccessHostProtocol` 의
  NSObject 구현. 16개 NFS callback 을 13개 fsaccess_mount message 로 환원.
- `daemon/MountPointSupervisor.swift` — `~/NoctilucaFS` startup probe (mkdir /
  forced umount / non-empty 거절).
- `daemon/NetFSMountController.swift` — `NetFS.framework` 의
  `NetFSMountURLAsync` 직접 호출로 user-level NFS 마운트. unmount 는 BSD
  `unmount(2, MNT_FORCE)` (NetFS 자체에는 unmount 진입점이 없음).
  `kNetFSAllowLoopbackKey = true` / `kNetFSMountAtMountDirKey = true` /
  `kNetFSSoftMountKey = true` / `kNAUIOptionNoUI` 옵션 사용.

# Channel direction

| Channel | host (consuming) | navigator (exposing) |
|---|---|---|
| `fsaccess` (control) | `.local` (발신) | `.remote` (수신) |
| `fsaccess_mount` (data) | `.local` (발신) | `.remote` (수신) |

`NoctilucaFeatureProvider.createChannel` 에서 `handle.direction == .remote` 인
fsaccess / fsaccess_mount 시도는 거절합니다 — host 는 *발신만* 합니다.

# Spec Violation Policy 적용 매트릭스

CLAUDE.md `<spec-violation-policy>` 의 분류에 따른 host 측 처리:

| 위반 | 분류 | 응답 |
|---|---|---|
| `FileSystemListResponse.entries` 수 ≤ 32 | 정상 | accept |
| `FileSystemListResponse.entries` 수 33–48 | warn-and-recover | warn 로그 + accept (truncate 안 함; spec 위반은 송신측 issue 로 간주) |
| `FileSystemListResponse.entries` 수 > 1024 | security-critical | channel close (현재 ServerNoticeCode 에 `quotaExceeded` 가 없어 `protocolViolation` 으로 escalate) |
| 미정의 opcode 응답 | warn-and-recover (응답이라 channel close 까지는 안 함) | warn 로그 + drop |
| FileSystemMountResponse 가 unknown requestId | warn-and-recover | warn 로그 + drop |
| navigator 응답이 success=false + ErrorInfo(code: \*) | 정상 (정상 에러 흐름) | NSError 로 변환 후 데몬에 reply |

# Daemon 통합

## host → daemon (NSXPCConnection, anonymous endpoint)

| 메서드 | 시점 |
|---|---|
| `daemonReady` | 호스트 앱 startup → `NocFSAccessDaemonHost.startupIfEnabled` 안에서. |
| `addConnection(connectionLabel, displayName)` | (Future) FSAccessChannel 의 List 응답 도착 직후. |
| `addMountSession(descriptor)` | (Future) FSAccessChannel 의 Mount 응답 success 시. |
| `removeMountSession(id)` | (Future) Unmount 응답 후 또는 mount channel close 시. |
| `removeConnection(label)` | (Future) fsaccess control channel close 시. |
| `shutdownGracefully` | NoctilucaServer.shutdown → `NocFSAccessDaemonHost.shutdownAndUnmount`. |

## daemon → host (reverse-XPC)

| 메서드 | 환원 |
|---|---|
| `lookup(parent, name)` | fsaccess_mount Stat(path) + new host handleId 발급 |
| `lookupParent(handle)` | path 의 parent segment 를 떼어 Stat |
| `getattr(handle)` | navigator handle 있으면 FStat, 없으면 Stat |
| `setattr(handle, patch)` | size 변경만 FTruncate, 그 외는 best-effort NOOP |
| `access(handle, mask)` | mask 그대로 echo (실 권한 검사는 navigator 측 read 시점) |
| `readdir(handle, ...)` | (필요 시) Open(directoryOnly) → ReadDir |
| `readlink(handle)` | Stat(followSymlinks=false) 의 symlinkTarget |
| `open(parent, name, ...)` | path 조립 → Open. 응답 handleId 를 host pathMap 에 attach. |
| `close(handle)` | navigator handle 있으면 Close, host pathMap 에서 unregister |
| `read(handle, ...)` | navigator handle 로 Read |
| `write(handle, ...)` | navigator handle 로 Write |
| `commit(handle, ...)` | Flush |
| `create(parent, name, type, attrs)` | type 이 directory 면 Mkdir, 아니면 Open(createNew) |
| `remove(parent, name)` | Stat 으로 type 판별 후 Rmdir / Unlink |
| `rename(srcParent, srcName, dstParent, dstName)` | Rename(oldPath, newPath) |
| `link(...)` | ENOTSUP (fsaccess_mount 에 hardlink 가 없음) |

# 미완성 / 향후 작업

- **NoctilucaClientSession 자동 wiring**: 인증 완료 시 fsaccess control channel
  자동 시작 + connectionLabel 발급 + List/Mount 자동 트리거. 현재는 채널 핸들러
  / FeatureProvider 등록까지만 되어 있고, host 가 채널을 *발신* 하는 트리거는
  외부 수단으로 호출해야 함.
- **ServerNoticeCode 보강**: `quotaExceeded` 케이스 신설.
- **streaming read/write**: `FileSystemRequestStreamRead` /
  `FileSystemRequestStreamWrite` 미구현 (현재는 단순 read/write 만).
