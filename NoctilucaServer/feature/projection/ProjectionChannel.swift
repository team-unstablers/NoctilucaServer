//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit
import AppKit

class ProjectionChannel: Channel {
    let logger = NoctilucaLogger(category: "ProjectionChannel")

    private let cursorStateHolder = CursorStateHolder.shared
    private var subscription: CursorEventSubscription? = nil

    /// Display 변경 이벤트 구독
    var displaySubscription: DisplayEventSubscription? = nil

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

        // cursor subscription 정리
        self.subscription?.destroy()
        self.subscription = nil

        // display subscription 정리
        self.displaySubscription?.destroy()
        self.displaySubscription = nil
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

        // displayman opcodes
        case .displayListRequest:
            let request = try DisplayListRequest.fromProtobufBytes(frame.data)
            try await self.handleDisplayListRequest(request)
        case .subscribeDisplayChangesRequest:
            let request = try SubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await self.handleSubscribeDisplayChangesRequest(request)
        case .unsubscribeDisplayChangesRequest:
            let request = try UnsubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeDisplayChangesRequest(request)

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
            
            var negotiatedCodec = negotiator.negotiate(with: request.preferredCodecs)
            
            guard var negotiatedCodec else {
                fatalError("Failed to negotiate codec for projection session")
            }
            
            // FIXME
            if let desiredSize = request.preferredCodecs.compactMap({ $0.size }).first {
                negotiatedCodec = Codec(
                    fourCC: negotiatedCodec.fourCC,
                    frameRate: negotiatedCodec.frameRate,
                    size: desiredSize,
                    options: negotiatedCodec.options,
                    quality: negotiatedCodec.quality
                )
            } else {
                let contentSize = await request.viewport.contentSize
                
                negotiatedCodec = Codec(
                    fourCC: negotiatedCodec.fourCC,
                    frameRate: negotiatedCodec.frameRate,
                    size: contentSize,
                    options: negotiatedCodec.options,
                    quality: negotiatedCodec.quality
                )
            }
            
            let channel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            
            self.logger.info("Opened ProjectionDataChannel with id: \(channel.identifier)")
            
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


fileprivate extension ProjectionSource {
    @MainActor
    var contentSize: SRSize? {
        switch value {
        case .entireDisplay(let source):
            let layoutManager = DisplayLayoutManager.shared
            let displayID = switch (source.displayID) {
            case -1:
                layoutManager.displayLayouts.keys.first { CGDisplayIsMain($0) != 0 }!
            case -2:
                fatalError("entire display layout is not supported yet")
            default:
                CGDirectDisplayID(source.displayID)
            }
            
            if let displaySize = DisplayLayoutManager.shared.displayLayouts[displayID]?.frame.size {
                return SRSize(width: displaySize.width, height: displaySize.height)
            } else {
                return nil
            }
            
        case .region(let region):
            return SRSize(width: region.region.width, height: region.region.height)
            
        case .singleWindow(let window):
            fatalError("not implemented yet")
            
        default:
            return nil
        }
    }
}
