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
            
            let channel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            print("Opened ProjectionDataChannel with id: \(channel.identifier)")
            let projectionSession = ProjectionSession(id: identifier, dataChannel: channel)
            
            try await projectionSession.prepare()
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
