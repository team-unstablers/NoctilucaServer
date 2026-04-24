//
//  NoctilucaFeatureProvider.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit

final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

    // FIXME: 이거 제거해야 함
    actor State {
        weak var clipboardChannel: ClipboardChannel?
        
        func setClipboardChannel(_ ch: ClipboardChannel?) {
            self.clipboardChannel = ch
        }
        
        func getClipboardChannel() -> ClipboardChannel? {
            return self.clipboardChannel
        }
    }
    
    func supportedFeatures() -> Set<SiriusFeature> {
        return [
            .hidio,
            .projection,
            .transfer,
            .clipboard
        ]
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
            return .accepted(ProjectionChannel(handle: handle))

        case .projectionData:
            return .accepted(ProjectionDataChannel(handle: handle))

        case .transfer:
            // 정책 게이트: remote가 TransferChannel을 열려고 할 때, 채널 자체를 만들기 전에
            // clipboard 설정(enabled / allowFile)을 먼저 확인하여 공격 표면을 줄인다.
            if handle.direction == .remote,
               let argsSet = TransferChannelArgumentsSet.parse(from: args) {
                let clip = await SettingsStore.shared.settings.clipboard
                guard clip.enabled else {
                    return .rejected(code: -1, reason: "Clipboard is disabled by policy")
                }
                if argsSet.purpose == .fileTransfer && !clip.allowFile {
                    return .rejected(code: -1, reason: "File transfer is disabled by policy")
                }
            }

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
                            await clip?.serveTransferData(channel,
                                                    itemIndex: itemIdx,
                                                    representationIndex: reprIdx)
                        }
                    }
                case .fileTransfer(let name, let path, let offset, let length):
                    if let path = path {
                        channel.onReady = {
                            Task {
                                let clip = await state.getClipboardChannel()
                                await clip?.serveFileTransferData(channel,
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
