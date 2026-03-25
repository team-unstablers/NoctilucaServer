//
//  NoctilucaFeatureProvider.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient

class NoctilucaFeatureProvider: FeatureProvider {
    private weak var clipboardChannel: ClipboardChannel?
    weak var progressTracker: FileTransferProgressTracker?

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
    
    func createChannel(for feature: SiriusKitClient.SiriusFeature,
                       using streamHolder: SiriusKitClient.StreamHolder,
                       identifier: SiriusKitClient.ChannelIdentifier,
                       direction: SiriusKitClient.ChannelDirection,
                       args: [String]) async throws -> ChannelCreationResult {
        
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
                    channel.onTransferStarted = { channelID, totalSize in
                        Task { @MainActor in tracker.register(channelID: channelID, totalSize: totalSize) }
                    }
                    channel.onProgressUpdate = { channelID, additionalBytes in
                        Task { @MainActor in tracker.update(channelID: channelID, additionalBytes: additionalBytes) }
                    }
                    channel.onTransferCompleted = { channelID in
                        Task { @MainActor in tracker.unregister(channelID: channelID) }
                    }
                }

                if channel.shouldSend() {
                    switch channel.task {
                    case .clipboardData(let itemIdx, let reprIdx):
                        clipboardChannel?.serveTransferData(channel, itemIndex: itemIdx, representationIndex: reprIdx)
                    case .fileTransfer(let name, let path, let offset, let length):
                        if let path = path {
                            clipboardChannel?.serveFileTransferData(channel, name: name, path: path, offset: offset, length: length)
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
