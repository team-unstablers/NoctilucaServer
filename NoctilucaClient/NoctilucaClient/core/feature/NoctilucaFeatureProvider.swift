//
//  NoctilucaFeatureProvider.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient

final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

    /// 채널 생성 시점에 NoctilucaClient 에 도달하기 위한 weak 참조.
    /// `NoctilucaClientManager.createClient` 가 client 생성 직후 set 한다.
    nonisolated(unsafe) private(set) weak var noctilucaClient: NoctilucaClient?

    actor State {
        weak var clipboardChannel: ClipboardChannel?
        weak var progressTracker: FileTransferProgressTracker?

        func setClipboardChannel(_ ch: ClipboardChannel?) {
            self.clipboardChannel = ch
        }

        func getClipboardChannel() -> ClipboardChannel? {
            return self.clipboardChannel
        }

        func setProgressTracker(_ t: FileTransferProgressTracker?) {
            self.progressTracker = t
        }

        func getProgressTracker() -> FileTransferProgressTracker? {
            return self.progressTracker
        }
    }

    /// `RemoteSession` 생성 직후에 호출되어 TransferChannel 진행률 추적을 연결한다.
    func setProgressTracker(_ tracker: FileTransferProgressTracker?) async {
        await state.setProgressTracker(tracker)
    }

    /// `NoctilucaClientManager.createClient` 가 호출하여 NoctilucaClient 와 연결한다.
    func setNoctilucaClient(_ client: NoctilucaClient?) async {
        self.noctilucaClient = client
    }

    func supportedFeatures() -> [SiriusFeature] {
        return [
            .hidio,
            .projection,
            .transfer,
            .clipboard,
            .fileSystemAccess,
            .fileSystemAccessMount,
            .simpleRPC,
        ]
    }

    func supports(_ feature: SiriusKitClient.SiriusFeature) -> Bool {
        switch feature {
        case .hidio:
            return true
        case .projection:
            return true
        case .projectionData:
            return true

        case .transfer:
            return true

        case .clipboard:
            return true

        case .fileSystemAccess:
            return true
        case .fileSystemAccessMount:
            return true

        case .simpleRPC:
            return true

        default:
            return false
        }
    }

    func createChannel(
        for feature: SiriusKitClient.SiriusFeature,
        handle: ChannelHandle,
        args: [String]
    ) async throws -> ChannelCreationResult {

        switch feature {
        case .hidio:
            return .accepted(HIDIOChannel(handle: handle))
        case .projection:
            return .accepted(ProjectionChannel(handle: handle))
        case .projectionData:
            return .accepted(ProjectionDataChannel(handle: handle))

        case .transfer:
            // fsaccess-mount stream-write 라우팅: 가장 먼저 검사한다.
            // (incoming TransferChannel 의 args[0] 이 "fsaccess-mount" 인 경우)
            if handle.direction == .remote,
               let transferId = FSAccessStreamArgs.parseTransferId(args: args),
               let client = self.noctilucaClient {
                let routeAndChannel = await MainActor.run { () -> (FSAccessStreamRoute, FSAccessMountChannel)? in
                    guard let session = client.fsAccessRemoteSession else { return nil }
                    guard let route = session.fsAccessStreamRoute(forTransferId: transferId) else { return nil }
                    guard case .write = route.kind else { return nil }
                    guard let mountSession = session.fsAccessMountSession(forId: route.mountSessionId),
                          let mountChannel = mountSession.mountChannel else { return nil }
                    return (route, mountChannel)
                }
                if let (route, mountChannel) = routeAndChannel {
                    let result = try await TransferChannel.createIfAccepts(handle: handle, args: args)
                    if case .accepted(let channel as TransferChannel) = result {
                        channel.onReady = { [weak channel] in
                            guard let channel = channel else { return }
                            Task {
                                await mountChannel.handleStreamWriteIncoming(channel, route: route)
                                await MainActor.run {
                                    client.fsAccessRemoteSession?.removeFSAccessStreamRoute(transferId: transferId)
                                }
                            }
                        }
                    }
                    return result
                }
            }

            // 정책 게이트: remote(서버)가 TransferChannel을 열려고 할 때, 채널 자체를
            // 만들기 전에 세션의 clipboard 설정(enabled / allowFile)을 먼저 확인하여
            // 공격 표면을 줄인다. fsaccess-mount 등 clipboard 외 purpose 는 게이트 적용 대상 아님.
            if handle.direction == .remote,
               let argsSet = try? TransferChannelArgumentsSet.parse(from: args),
               argsSet.purpose == .fileTransfer || argsSet.purpose == .clipboardData {
                let clipSettings = await state.getClipboardChannel()?.clipboardSettings
                guard clipSettings?.enabled == true else {
                    return .rejected(code: -1, reason: "Clipboard is disabled by policy")
                }
                if argsSet.purpose == .fileTransfer && clipSettings?.allowFile != true {
                    return .rejected(code: -1, reason: "File transfer is disabled by policy")
                }
            }

            let result = try await TransferChannel.createIfAccepts(
                handle: handle,
                args: args
            )

            if case .accepted(let channel as TransferChannel) = result {
                let state = self.state

                // 진행률 콜백 배선
                if let tracker = await state.getProgressTracker() {
                    channel.onTransferStarted = { [weak tracker] channelID, totalSize in
                        Task { @MainActor in tracker?.register(channelID: channelID, totalSize: totalSize) }
                    }
                    channel.onProgressUpdate = { [weak tracker] channelID, additionalBytes in
                        Task { @MainActor in tracker?.update(channelID: channelID, additionalBytes: additionalBytes) }
                    }
                    channel.onTransferCompleted = { [weak tracker] channelID in
                        Task { @MainActor in tracker?.unregister(channelID: channelID) }
                    }
                }

                if channel.shouldSend() {
                    switch channel.task {
                    case .clipboardData(let itemIdx, let reprIdx):
                        channel.onReady = {
                            Task {
                                let clip = await state.getClipboardChannel()
                                clip?.serveTransferData(channel, itemIndex: itemIdx, representationIndex: reprIdx)
                            }
                        }
                    case .fileTransfer(let name, let path, let offset, let length):
                        if let path = path {
                            channel.onReady = {
                                Task {
                                    let clip = await state.getClipboardChannel()
                                    clip?.serveFileTransferData(channel, name: name, path: path, offset: offset, length: length)
                                }
                            }
                        }
                    default:
                        break
                    }
                }
            }

            return result

        case .clipboard:
            let channel = ClipboardChannel(handle: handle)
            await state.setClipboardChannel(channel)
            return .accepted(channel)

        case .fileSystemAccess:
            // direction == .remote 만 수락. 클라가 직접 .local 로 여는 시나리오는 의미가 없다.
            guard handle.direction == .remote else {
                return .rejected(code: -1, reason: "fsaccess control channel must be opened by the remote peer")
            }
            // 정책 게이트: deny 면 채널 생성 자체를 거부.
            if let client = self.noctilucaClient,
               let policy = await MainActor.run(body: { client.sessionSettings?.transfer.fsAccessPolicy }),
               policy == .deny {
                return .rejected(code: -1, reason: "fsaccess is disabled by client policy")
            }
            let channel = FSAccessChannel(handle: handle)
            return .accepted(channel)

        case .fileSystemAccessMount:
            // direction == .remote + sessionId 매칭 검증.
            guard handle.direction == .remote else {
                return .rejected(code: -1, reason: "fsaccess_mount channel must be opened by the remote peer")
            }
            guard let client = self.noctilucaClient else {
                return .rejected(code: -1, reason: "fsaccess_mount: NoctilucaClient unavailable")
            }
            guard let channel = await FSAccessMountChannel.createIfAccepts(handle: handle, args: args, client: client) else {
                return .rejected(code: -1, reason: "fsaccess_mount: sessionId in args does not match any active mount session")
            }
            return .accepted(channel)

        case .simpleRPC:
            // 클라이언트는 RPC 요청을 보내는 측만 지원. 서버가 .remote 로 열려는 시도는 거절.
            guard handle.direction == .local else {
                return .rejected(code: -1, reason: "SimpleRPC channel must be opened from client side")
            }
            return .accepted(SimpleRPCChannel(handle: handle))

        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
