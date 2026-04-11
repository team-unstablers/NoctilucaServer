//
//  NoctilucaFeatureProvider.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient

final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

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

    func supportedFeatures() -> [SiriusFeature] {
        return [
            .hidio,
            .projection,
            .transfer,
            .clipboard,
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

        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
