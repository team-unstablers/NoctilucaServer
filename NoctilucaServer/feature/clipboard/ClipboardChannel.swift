//
//  ClipboardChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import SiriusKit

class ClipboardChannel: Channel {
    let logger = NoctilucaLogger(category: "ClipboardChannel")

    private var remoteSubscription: ClipboardSubscription? = nil

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

        // omitted가 아닌 항목만 필터링하여 적용
        let filteredItems = event.items.map { item in
            ClipboardItem(representations: item.representations.filter {
                !$0.flags.contains(.omitted) && $0.data != nil
            })
        }.filter { !$0.representations.isEmpty }

        guard !filteredItems.isEmpty else { return }

        logger.info("Applying remote clipboard event (\(filteredItems.count) items)")
        await ClipboardManager.shared.set(items: filteredItems)
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
        if let subscription = remoteSubscription {
            Task { @MainActor in
                subscription.destroy()
            }
            remoteSubscription = nil
        }
        super.handleStreamClose()
    }

    override func handleStreamError(error: any Error) {
        logger.error("ClipboardChannel stream error: \(error)")
        if let subscription = remoteSubscription {
            Task { @MainActor in
                subscription.destroy()
            }
            remoteSubscription = nil
        }
        super.handleStreamError(error: error)
    }
}
