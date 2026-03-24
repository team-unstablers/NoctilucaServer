//
//  ClipboardChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation

import SiriusKit

class ClipboardChannel: Channel {
    let logger = NoctilucaLogger(category: "ClipboardChannel")

    private var remoteSubscription: ClipboardSubscription? = nil

    /// 마지막으로 보낸 ClipboardEvent의 omitted 데이터 스냅샷 (transfer 요청 응답용)
    private var lastSentSnapshot: ClipboardDataSnapshot? = nil

    /// 현재 진행 중인 resolve 작업 (취소 가능)
    private var resolveTask: Task<Void, Never>? = nil

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .clipboardEvent:
            let event = try ClipboardEvent.fromProtobufBytes(frame.data)
            try await self.handleClipboardEvent(event)

        case .getClipboardRequest:
            let request = try GetClipboardRequest.fromProtobufBytes(frame.data)
            try await self.handleGetClipboardRequest(request)

        case .getClipboardResponse:
            let response = try GetClipboardResponse.fromProtobufBytes(frame.data)
            try await self.handleGetClipboardResponse(response)

        case .subscribeClipboardRequest:
            let request = try SubscribeClipboardRequest.fromProtobufBytes(frame.data)
            try await self.handleSubscribeClipboardRequest(request)
        case .subscribeClipboardResponse:
            let response = try SubscribeClipboardResponse.fromProtobufBytes(frame.data)
            try await self.handleSubscribeClipboardResponse(response)
        case .unsubscribeClipboardRequest:
            let request = try UnsubscribeClipboardRequest.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeClipboardRequest(request)
        case .unsubscribeClipboardResponse:
            let response = try UnsubscribeClipboardResponse.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeClipboardResponse(response)

        default:
            logger.warning("Received unknown opcode: \(frame.opcode)")
        }
    }

    // MARK: - Snapshot Management

    /// ClipboardSubscription에서 이벤트 발송 시 omitted 데이터 스냅샷을 저장합니다.
    func storeSnapshot(_ snapshot: ClipboardDataSnapshot) {
        self.lastSentSnapshot = snapshot
    }

    // MARK: - Transfer Serving

    /// FeatureProvider로부터 호출됨: 상대방이 clipboard-data TransferChannel을 열었을 때
    func serveTransferData(_ transferChannel: TransferChannel, itemIndex: Int, representationIndex: Int) {
        Task {
            guard let data = lastSentSnapshot?.get(itemIndex: itemIndex, reprIndex: representationIndex) else {
                logger.warning("No snapshot data for item=\(itemIndex), repr=\(representationIndex)")
                try? await transferChannel.close()
                return
            }

            do {
                try await transferChannel.sendStartNotification(TransferStartNotification(
                    name: "clipboard-data",
                    totalSize: UInt64(data.count),
                    contentType: "application/octet-stream",
                    description: "Omitted clipboard data (item=\(itemIndex), repr=\(representationIndex))",
                    sha256sum: Data()
                ))
                try await transferChannel.write(data)
            } catch {
                logger.error("Failed to serve clipboard transfer: \(error)")
            }
        }
    }

    // MARK: - Request Handlers (클라이언트 → 서버)

    private func handleSubscribeClipboardRequest(_ request: SubscribeClipboardRequest) async throws {
        let settings = SettingsStore.shared.settings.clipboard

        guard settings.enabled else {
            logger.info("Clipboard disabled, rejecting subscribe request (requestId=\(request.requestId))")
            try await send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
                requestId: request.requestId,
                subscriptionId: nil
            ))
            return
        }

        // 기존 구독이 있으면 제거
        if let existing = remoteSubscription {
            await existing.destroy()
            remoteSubscription = nil
        }

        let subscription = ClipboardSubscription()
        subscription.channel = self
        await subscription.setup()

        remoteSubscription = subscription

        logger.info("Clipboard subscription created (id=\(subscription.id), requestId=\(request.requestId))")

        try await send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
            requestId: request.requestId,
            subscriptionId: subscription.id
        ))
    }

    private func handleUnsubscribeClipboardRequest(_ request: UnsubscribeClipboardRequest) async throws {
        guard let subscription = remoteSubscription else {
            logger.warning("No active subscription to unsubscribe (requestId=\(request.requestId))")
            try await send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
                requestId: request.requestId,
                subscriptionId: request.subscriptionId,
                isSuccess: false
            ))
            return
        }

        let subscriptionId = subscription.id
        await subscription.destroy()
        remoteSubscription = nil

        logger.info("Clipboard subscription removed (id=\(subscriptionId), requestId=\(request.requestId))")

        try await send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId,
            isSuccess: true
        ))
    }

    private func handleGetClipboardRequest(_ request: GetClipboardRequest) async throws {
        let settings = SettingsStore.shared.settings.clipboard

        guard settings.enabled else {
            logger.info("Clipboard disabled, rejecting get request (requestId=\(request.requestId))")
            try await send(opcode: .getClipboardResponse, message: GetClipboardResponse(
                requestId: request.requestId,
                success: false,
                items: []
            ))
            return
        }

        let items = await ClipboardManager.shared.current()

        try await send(opcode: .getClipboardResponse, message: GetClipboardResponse(
            requestId: request.requestId,
            success: true,
            items: items
        ))
    }

    private func handleClipboardEvent(_ event: ClipboardEvent) async throws {
        let settings = SettingsStore.shared.settings.clipboard

        guard settings.enabled else { return }

        // syncDirection 체크: remoteToLocal 또는 bidirectional일 때만 적용
        guard settings.syncDirection == .remoteToLocal ||
              settings.syncDirection == .bidirectional else {
            return
        }

        // 진행 중인 resolve 취소
        resolveTask?.cancel()

        resolveTask = Task { [weak self] in
            guard let self = self else { return }

            var resolvedItems: [ClipboardItem] = []

            for (itemIndex, item) in event.items.enumerated() {
                var resolvedRepresentations: [ClipboardData] = []

                for (reprIndex, representation) in item.representations.enumerated() {
                    guard !Task.isCancelled else { return }

                    if representation.flags.contains(.omitted) {
                        if let data = try? await self.resolveOmittedData(
                            itemIndex: itemIndex, reprIndex: reprIndex
                        ) {
                            resolvedRepresentations.append(ClipboardData(
                                contentType: representation.contentType,
                                size: UInt64(data.count),
                                data: data,
                                flags: []
                            ))
                        } else {
                            self.logger.warning("Failed to resolve omitted data (item=\(itemIndex), repr=\(reprIndex))")
                        }
                    } else if representation.data != nil {
                        resolvedRepresentations.append(representation)
                    }
                }

                if !resolvedRepresentations.isEmpty {
                    resolvedItems.append(ClipboardItem(representations: resolvedRepresentations))
                }
            }

            guard !Task.isCancelled, !resolvedItems.isEmpty else { return }

            self.logger.info("Applying remote clipboard event (\(resolvedItems.count) items)")
            await ClipboardManager.shared.set(items: resolvedItems)
        }
    }

    // MARK: - Omitted Data Resolve

    private func resolveOmittedData(itemIndex: Int, reprIndex: Int) async throws -> Data? {
        guard let session = self.clientSession else { return nil }

        let argsSet = TransferChannelArgumentsSet(
            purpose: .clipboardData,
            direction: .download,
            args: [String(itemIndex), String(reprIndex)]
        )

        guard let channel = try await session.channelManager.openChannel(
            for: .transfer,
            identifier: ChannelIdentifier(),
            args: argsSet.serialize()
        ) as? TransferChannel else {
            return nil
        }

        guard let dataStream = channel.dataStream else { return nil }

        var data = Data()
        for await chunk in dataStream {
            data += chunk
        }

        return data.isEmpty ? nil : data
    }

    // MARK: - Response Handlers (서버 → 클라이언트 요청의 응답, 현재 미사용)

    private func handleGetClipboardResponse(_ response: GetClipboardResponse) async throws {
        logger.debug("Received GetClipboardResponse (requestId=\(response.requestId), success=\(response.success)) - not implemented")
    }

    private func handleSubscribeClipboardResponse(_ response: SubscribeClipboardResponse) async throws {
        logger.debug("Received SubscribeClipboardResponse (requestId=\(response.requestId)) - not implemented")
    }

    private func handleUnsubscribeClipboardResponse(_ response: UnsubscribeClipboardResponse) async throws {
        logger.debug("Received UnsubscribeClipboardResponse (requestId=\(response.requestId)) - not implemented")
    }

    // MARK: - Stream Lifecycle

    override func handleStreamClose() {
        resolveTask?.cancel()
        if let subscription = remoteSubscription {
            Task { @MainActor in
                subscription.destroy()
            }
            remoteSubscription = nil
        }
        lastSentSnapshot = nil
        super.handleStreamClose()
    }

    override func handleStreamError(error: any Error) {
        logger.error("ClipboardChannel stream error: \(error)")
        resolveTask?.cancel()
        if let subscription = remoteSubscription {
            Task { @MainActor in
                subscription.destroy()
            }
            remoteSubscription = nil
        }
        lastSentSnapshot = nil
        super.handleStreamError(error: error)
    }
}
