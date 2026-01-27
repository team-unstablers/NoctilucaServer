//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit
import AppKit

class ProjectionChannel: Channel {
    private let logger = NoctilucaLogger(category: "ProjectionChannel")
    
    private let cursorStateHolder = CursorStateHolder.shared
    private var subscription: CursorEventSubscription? = nil
    
    private(set) var sessions: [UUID: ProjectionSession] = [:]

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
        
        assert(direction == .remote, "ProjectionChannel must be opened from remote side")
    }
    
    // FIXME: 채널 닫고 그래야 함
    func destroy() async {
        for session in self.sessions.values {
            do {
                try await session.stop()
            } catch {
                self.logger.error("Failed to stop projection session \(session.id): \(error)")
            }
        }
        
        self.sessions.removeAll()
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        switch frame.opcode {
        case .projectionRequest:
            let projectionRequest = try ProjectionRequest.fromProtobufBytes(frame.data)
            await self.handleProjectionRequest(consume projectionRequest)
        case .projectionPerformanceReport:
            let report = try ProjectionPerformanceReport.fromProtobufBytes(frame.data)
            await self.handlePerformanceReport(report)
        case .subscribeCursorEventsRequest:
            let request = try SubscribeCursorEventsRequest.fromProtobufBytes(frame.data)
            try await self.handleSubscribeCursorEventsRequest(request)
        case .unsubscribeCursorEventsRequest:
            let request = try UnsubscribeCursorEventsRequest.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeCursorEventsRequest(request)
            
        default:
            print("Unhandled opcode in ProjectionChannel: \(frame.opcode)")
            break
        }
    }
    
    private func handlePerformanceReport(_ report: ProjectionPerformanceReport) async {
        guard let session = self.sessions[report.identifier] else {
            self.logger.warning("Received performance report for unknown session \(report.identifier)")
            return
        }
        
        session.handlePerformanceReport(report)
    }
    
    func handleProjectionRequest(_ request: ProjectionRequest) async {
        guard let session = self.clientSession else {
            return
        }
        
        do {
            let identifier = request.identifier
            
            let projectionSettings = NoctilucaServer.shared.settings.projection
            let negotiator = CodecNegotiator.create(
                from: projectionSettings.codecNegotiationPolicy,
                specifications: projectionSettings.codecSpecifications
            )
            
            let negotiatedCodec = negotiator.negotiate(with: request.preferredCodecs)
            
            guard let negotiatedCodec else {
                // TODO: error 던져야 함
                self.logger.error("Failed to negotiate codec for projection session")
                return
            }
            
            let channel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            print("Opened ProjectionDataChannel with id: \(channel.identifier)")
            let projectionSession = ProjectionSession(
                id: identifier,
                dataChannel: channel,
                preferredRecorderType: projectionSettings.preferredScreenRecorder
            )
            
            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()
            
            self.sessions[identifier] = projectionSession
            
            try await self.send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: negotiatedCodec
            ))
        } catch {
            self.logger.error("Failed to handle projection request: \(error)")
        }
    }
    
    private func handleSubscribeCursorEventsRequest(_ request: SubscribeCursorEventsRequest) async throws {
        if let subscription = self.subscription {
            // TODO: send error
            return
        }
        
        let subscription = CursorEventSubscription()
        subscription.channel = self
        
        await subscription.setup()
        
        self.subscription = subscription
        
        try await self.send(opcode: .subscribeCursorEventsResponse, message: SubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id
        ))
    }
    
    private func handleUnsubscribeCursorEventsRequest(_ request: UnsubscribeCursorEventsRequest) async throws {
        guard let subscription = self.subscription else {
            // TODO: send error
            return
        }
        
        subscription.destroy()
        self.subscription = nil

        try await self.send(opcode: .unsubscribeCursorEventsResponse, message: UnsubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id,
            isSuccess: true
        ))
    }
    
    func sendCursorEvent() async throws {
        guard let cursorImage = await cursorStateHolder.cursorImage,
              let png = cursorImage.pngData()
        else {
            return
        }
        
        try await self.send(opcode: .cursorEvent, message: CursorEvent(
            cursorType: UInt64(cursorStateHolder.cursorHash),
            mimeType: "image/png",
            size: SRSize(width: cursorImage.size.width, height: cursorImage.size.height),
            imageData: png
        ))
    }
}

