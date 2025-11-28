//
//  NoctilucaClient.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

import SiriusKitClient

class NoctilucaClient {
    private let logger = SiriusLogger(category: "NoctilucaClient", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    let session: SiriusClient
    
    init(_ session: SiriusClient) {
        self.session = session
        
        self.session.delegate = self
    }
    
    func setup() async throws {
        try await session.setup()
    }
    
    func startup() async throws {
        logger.info("Starting up NoctilucaClient...")
        try await session.startup()
    }
}


extension NoctilucaClient: SiriusClientDelegate {
    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel) {
        logger.info("Main channel created with ID: \(mainChannel.identifier)")
        
        Task {
            try await mainChannel.sendClientHello(ClientHello(protocolVersion: .v1_0, agentName: "NoctilucaClient TEST"))
            
            for await event in mainChannel.events {
                switch event {
                case .receivedServerHello(let message):
                    logger.info("Received ServerHello: protocolVersion=\(message.protocolVersion), serverName=\(message.serverName)")
                default:
                    break
                }
            }
        }
    }
}
