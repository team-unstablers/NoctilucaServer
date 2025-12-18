//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation

import SiriusKitClient

class ProjectionChannel: Channel {
    private let logger = SiriusLogger(category: "ProjectionChannel", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    
    private(set) var pendingSessions: [UUID: () -> Void] = [:]
    private(set) var sessions: [UUID: ProjectionSession] = [:]
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
        
        assert(direction == .local, "ProjectionChannel must be opened from client side")
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        switch frame.opcode {
        case .projectionSessionCreatedEvent:
            let event = try ProjectionSessionCreatedEvent.fromProtobufBytes(frame.data)
            self.logger.info("Received ProjectionSessionCreatedEvent: sessionId=\(event.identifier)")
            if let continuation = self.pendingSessions[event.identifier] {
                continuation()
            } else {
                self.logger.warning("No pending session found for identifier: \(event.identifier)")
            }
            
        default:
            break
        }
    }
    
    func createSession() async throws -> ProjectionSession {
        guard let clientSession = self.clientSession else {
            fatalError()
        }
        
        let identifier = UUID()
        
        try await self.send(opcode: .projectionRequest, message: ProjectionRequest(
            identifier: identifier,
            viewport: ProjectionSource(value: .entireDisplay(EntireDisplayProjectionSource(displayID: Int32(-1))),
                                       flags: .none),
            preferredCodecs: [
                Codec(
                    fourCC: .hvc1, // 'HVC1',
                    frameRate: 30,
                    size: CGSize(width: 1920, height: 1080),
                    options: "hardware-acceleration: 'true'",
                    quality: .variableBitrate(targetBitrateKbps: 1200, maxBitrateKbps: 2400)
                )
            ]
        ))
        
        await withCheckedContinuation { cont in
            self.pendingSessions[identifier] = {
                self.pendingSessions.removeValue(forKey: identifier)
                cont.resume()
            }
        }
        
        let channel = clientSession.channelManager.channels[identifier] as! ProjectionDataChannel
        
        let session = ProjectionSession(id: identifier, dataChannel: channel, controlChannel: self)
        
        try await session.prepare()
        try await session.start()
        
        self.sessions[identifier] = session
        return session
    }
    

}
