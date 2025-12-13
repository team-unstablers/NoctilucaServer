//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit

class ProjectionChannel: Channel {
    private let logger = NoctilucaLogger(category: "ProjectionChannel")
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
            
        default:
            print("Unhandled opcode in ProjectionChannel: \(frame.opcode)")
            break
        }
    }
    
    func handleProjectionRequest(_ request: ProjectionRequest) async {
        guard let session = self.clientSession else {
            return
        }
        
        do {
            let identifier = request.identifier
            
            let negotiator = CodecNegotiator.create(from: .balanced, specifications: NoctilucaServer.shared.settings.projection.codecSpecifications)
            
            let specification = negotiator.negotiate(with: request.preferredCodecs)
            
            guard let specification else {
                // TODO: error 던져야 함
                self.logger.error("Failed to negotiate codec for projection session")
                return
            }
            
            let channel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            print("Opened ProjectionDataChannel with id: \(channel.identifier)")
            let projectionSession = ProjectionSession(id: identifier, dataChannel: channel)
            
            try await projectionSession.prepare(specification, desiredSize: request.preferredCodecs.first?.size)
            try await projectionSession.start()
            
            self.sessions[identifier] = projectionSession
            
            try await self.send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: request.preferredCodecs.first!
            ))
        } catch {
            self.logger.error("Failed to handle projection request: \(error)")
        }
    }
}
