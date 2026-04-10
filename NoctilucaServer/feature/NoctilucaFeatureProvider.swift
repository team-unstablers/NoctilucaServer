//
//  NoctilucaFeatureProvider.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit

final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

    actor State {
        weak var clipboardChannel: ClipboardChannel?
        
        func setClipboardChannel(_ ch: ClipboardChannel?) {
            self.clipboardChannel = ch
        }
        
        func getClipboardChannel() -> ClipboardChannel? {
            return self.clipboardChannel
        }
    }

    func supports(_ feature: SiriusFeature) -> Bool {
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

        case .projection:
            // TODO: 후속 PR 에서 v2 로 이식.
            fatalError("TODO: projection channel v2 migration pending")
            
        case .projectionData:
            // TODO: 후속 PR 에서 v2 로 이식.
            fatalError("TODO: projectionData channel v2 migration pending")

        case .transfer:
            let result = try await TransferChannel.createIfAccepts(
                handle: handle,
                args: args
            )

            if case .accepted(let channel as TransferChannel) = result,
               channel.shouldSend() {
                let state = self.state
                switch channel.task {
                case .clipboardData(let itemIdx, let reprIdx):
                    channel.onReady = {
                        Task {
                            let clip = await state.getClipboardChannel()
                            clip?.serveTransferData(channel,
                                                    itemIndex: itemIdx,
                                                    representationIndex: reprIdx)
                        }
                    }
                case .fileTransfer(let name, let path, let offset, let length):
                    if let path = path {
                        channel.onReady = {
                            Task {
                                let clip = await state.getClipboardChannel()
                                clip?.serveFileTransferData(channel,
                                                            name: name, path: path,
                                                            offset: offset, length: length)
                            }
                        }
                    }
                default:
                    break
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
