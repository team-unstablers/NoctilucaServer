//
//  NoctilucaClientSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import SiriusKit

struct ClientInfo {
    let agentName: String
    let protocolVersion: SiriusProtocolVersion
}

enum NoctilucaClientSessionError: LocalizedError {
    case unsupportedProtocolVersion
}

class NoctilucaClientSession: Identifiable {
    private let logger = SiriusLogger(category: "NoctilucaClientSession", subsystem: "pl.unstabler.noctiluca.NoctilucaServer")
    
    var id: UUID { session.id }
    
    let session: ClientSession
    let server: ServerContext
    
    var mainChannel: MainChannel!
    
    var clientInfo: ClientInfo? = nil
    
    private var eventLoopTask: Task<Void, Never>?
    
    init(session: ClientSession, server: ServerContext) {
        self.session = session
        self.server = server
        
        self.session.delegate = self
    }
    
    private func mainChannelEventLoop() async {
        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedClientHello(let message):
                    try await handleClientHello(message)
                case .receivedAuthRequest(let message):
                    try await handleAuthRequest(message)
                default:
                    // ignore other events
                    break
                }
            }
        } catch {
            print("Error in mainChannelEventLoop: \(error)")
            // crash()
        }
    }
    
    private func handleClientHello(_ message: ClientHello) async throws {
        logger.info("Received ClientHello from agent: \(message.agentName), protocol version: \(message.protocolVersion)")
        
        // negotiate protocol version, features, etc.
        let clientInfo = ClientInfo(
            agentName: message.agentName,
            protocolVersion: message.protocolVersion
        )
        
        self.clientInfo = clientInfo
        
        guard clientInfo.protocolVersion == .v1_0 else {
            throw NoctilucaClientSessionError.unsupportedProtocolVersion
        }
        
        // respond with ServerHello
        let response = ServerHello(
            protocolVersion: .v1_0,
            supportedFeatures: [
                // ...
            ],
            serverName: "\(NoctilucaMeta.productName)/\(NoctilucaMeta.version)",
            motd: "FIXME"
        )
        
        try await self.mainChannel.sendServerHello(response)
        
        /*
        let challenge = AuthChallenge(
            acceptedMethods: server.authenticator.supportedMethods(),
            message: nil
        )
        
        try await self.mainChannel.sendAuthChallenge(challenge)
         */
    }
    
    private func handleAuthRequest(_ message: AuthRequest) async throws {
        // PAM.authenticate(message)
        
        let challenge = AuthChallenge(
            acceptedMethods: [
                .simplePassword
            ],
            message: nil
        )
        
        try await self.mainChannel.sendAuthChallenge(challenge)
        
        // ...
        
        session.shouldAcceptChannelCreation = true
        
        // ...
    }
}

extension NoctilucaClientSession: ClientSessionDelegate {
    func clientSessionDidCreateMainChannel(_ session: SiriusKit.ClientSession, mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        self.eventLoopTask = Task {
            await mainChannelEventLoop()
        }
    }
}
