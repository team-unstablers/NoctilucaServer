//
//  NoctilucaFeatureProvider.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient

final class NoctilucaFeatureProvider: FeatureProvider {
    // NOTE: HIDIO 외 feature(projection / projectionData / transfer / clipboard)
    //       의 v2 마이그레이션은 후속 PR 에서 수행한다.
    //       아래 `clipboardChannel` weak 참조, `progressTracker` weak 참조,
    //       `createChannelLegacy(...)` 는 후속 PR 에서 v2 로 이식할 때의 원본
    //       로직을 **완전한 형태로 보존**하기 위해 남겨 두었다. 현재 Channel
    //       프로토콜이 v2(handle 기반) 이므로 이 경로는 컴파일되지 않지만,
    //       "정보 손실 방지" 차원에서 일부러 보존한다. 후속 PR 에서 이 메서드를
    //       제거/재작성한다.
    private weak var clipboardChannel: ClipboardChannel?
    weak var progressTracker: FileTransferProgressTracker?

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
        for feature: SiriusFeature,
        handle: ChannelHandle,
        args: [String]
    ) async throws -> ChannelCreationResult {
        switch feature {
        case .hidio:
            return .accepted(HIDIOChannel(handle: handle))

        case .projection, .projectionData, .transfer, .clipboard:
            // TODO: 후속 PR 에서 v2 로 이식. 현재는 런타임 fatalError 로 두고
            //       원본 v1 로직은 아래 `createChannelLegacy(...)` 에 보존.
            fatalError("TODO: \(feature) channel v2 migration pending")

        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }

    // MARK: - Legacy v1 원본 로직 (후속 PR 마이그레이션용 참고)
    //
    // 아래 메서드는 Channel 레이어가 v1 base class 였을 때의 로직을 그대로 옮겨 둔 것이다.
    // 현재 v2 API 에서는 `streamHolder: StreamHolder`, `identifier: ChannelIdentifier`,
    // `direction: ChannelDirection` 인자가 존재하지 않고, 각 채널 init 시그니처도 달라져
    // 이 메서드는 **컴파일되지 않는다**. 후속 projection/transfer/clipboard PR 에서
    // 이 로직을 v2 로 이식하고 완전히 제거할 예정이다.

    private func createChannelLegacy(
        for feature: SiriusKitClient.SiriusFeature,
        using streamHolder: SiriusKitClient.StreamHolder,
        identifier: SiriusKitClient.ChannelIdentifier,
        direction: SiriusKitClient.ChannelDirection,
        args: [String]
    ) async throws -> ChannelCreationResult {

        switch feature {
        case .hidio:
            return .accepted(HIDIOChannel(using: streamHolder, identifier: identifier, direction: direction))
        case .projection:
            return .accepted(ProjectionChannel(using: streamHolder, identifier: identifier, direction: direction))
        case .projectionData:
            return .accepted(ProjectionDataChannel(using: streamHolder, identifier: identifier, direction: direction))

        case .transfer:
            let result = try await TransferChannel.createIfAccepts(
                streamHolder,
                identifier: identifier,
                direction: direction,
                args: args
            )

            if case .accepted(let channel as TransferChannel) = result {
                // 진행률 콜백 배선
                if let tracker = progressTracker {
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
                        channel.onReady = { [weak self] in
                            self?.clipboardChannel?.serveTransferData(channel, itemIndex: itemIdx, representationIndex: reprIdx)
                        }
                    case .fileTransfer(let name, let path, let offset, let length):
                        if let path = path {
                            channel.onReady = { [weak self] in
                                self?.clipboardChannel?.serveFileTransferData(channel, name: name, path: path, offset: offset, length: length)
                            }
                        }
                    default:
                        break
                    }
                }
            }

            return result

        case .clipboard:
            let channel = ClipboardChannel(using: streamHolder, identifier: identifier, direction: direction)
            self.clipboardChannel = channel
            return .accepted(channel)

        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
