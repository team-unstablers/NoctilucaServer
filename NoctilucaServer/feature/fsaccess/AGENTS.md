# fsaccess (consuming peer)

서버(NoctilucaServer = host)가 **consuming peer** 로서 fsaccess control / fsaccess_mount
channel 을 발신하고, host app 안의 ``NoctilucaNFSServer`` 가 NFS callback 을 직접
fsaccess_mount channel 호출로 dispatch 한다. navigator (NoctilucaClient) 가 노출하는
파일을 호스트 머신의 Finder 에 NFS 마운트로 띄우는 게 목표.

상위 설계는 `docs/fsaccess.md` 가 정본입니다.

# Files

- `FSAccessChannel.swift` — control channel (`handle.direction == .local`).
  List / Mount / Unmount 요청을 발신하고 응답을 typed continuation 으로 매칭.
- `FSAccessMountChannel.swift` — data channel. mount session 별 1 인스턴스.
  13개 fsaccess_mount message 발신 + `FSAccessMountReply` enum 으로 응답 unification.
  내부에 `MountSessionPathMap` (host-side handleId → path / navigator handle 매핑) 보관.
- `FSAccessConsumingState.swift` — control channel 의 inner state. List 응답 entries,
  mount session record, requestId 발급기.
- `FSAccessRequestRouter.swift` — process-wide actor. mountSessionId → 활성
  ``FSAccessMountChannel`` 매핑. ``NoctilucaNFSServer`` 가 NFS callback 처리 시 사용.
- `FSAccessChannelStartArgs.swift` — fsaccess_mount channel start args[0] 의 sessionId
  UUID 직렬화.
- `daemon/NocFSAccessHost.swift` — fsaccess feature 의 host-app supervisor.
  in-process 로 nanonfs `NFSServerListener` 를 띄우고 `VirtualTree` /
  `HandleTable` 을 보유. mount point probe + NetFS 마운트 lifecycle.
- `daemon/MountPointSupervisor.swift` — `~/NoctilucaFS` startup probe (mkdir /
  forced umount / non-empty 거절).
- `daemon/NetFSMountController.swift` — `NetFS.framework` 의
  `NetFSMountURLAsync` 직접 호출. unmount 는 BSD `unmount(MNT_FORCE)`.
- `nfs/NoctilucaNFSServer.swift` — `NFSServer` 채택 actor. 21개 callback 을
  fsaccess_mount channel 호출로 dispatch.
- `nfs/VirtualTree.swift` — 1단계 connection / 2단계 mount session 가상 트리 actor.
- `nfs/HandleTable.swift` — `NFSFileHandle.bytes` 인/디코드 + entry kind 보관.

> Note: 기존 디렉토리 이름은 `daemon/` 이지만 실제로는 별도 데몬이 없다 (in-process
> design). 이름은 1차 design 의 잔재이며 추후 정리 예정.

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
| `FileSystemListResponse.entries` 수 33–48 | warn-and-recover | warn 로그 + accept |
| `FileSystemListResponse.entries` 수 > 1024 | security-critical | channel close (`protocolViolation`; 후속 PR 에서 `quotaExceeded` 로 마이그레이션) |
| 미정의 opcode 응답 | warn-and-recover | warn 로그 + drop |
| FileSystemMountResponse 가 unknown requestId | warn-and-recover | warn 로그 + drop |
| navigator 응답이 success=false + ErrorInfo | 정상 (정상 에러 흐름) | NFSError 로 변환 |

# 미완성 / 향후 작업

- streaming read/write (`FileSystemRequestStreamRead` /
  `FileSystemRequestStreamWrite`) 경로.
- `ServerNoticeCode.quotaExceeded` 신설.
- consent policy `alwaysAsk` 의 macOS 알림 UI.
- `daemon/` 디렉토리를 `host/` 등으로 rename (별도 데몬이 사라졌으므로).
