//
//  NoctilucaClient+Auth.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Combine

import SiriusKitClient

extension NoctilucaClient {
    func initializeHIDIO() async throws {
        guard let channel = try await session.channelManager.openChannel(for: .hidio, identifier: ChannelIdentifier()) as? HIDIOChannel else {
            // FIXME
            return
        }
        
        self.hidioController = HIDIOController(channel: channel)
        
        self.logger.info("initializeHIDIO(): created HIDIOController")
    }
    
    func initializeProjection() async throws {
        guard let channel = try await session.channelManager.openChannel(for: .projection, identifier: ChannelIdentifier()) as? ProjectionChannel else {
            // FIXME
            return
        }
        
        self.projectionChannel = channel
        self.logger.info("initializeProjection(): created ProjectionChannel")
        
        let session = try await channel.createSession()
        self.logger.info("initializeProjection(): created sample session")
        
        await MainActor.run {
            self.uiEvents.send(.FIXME_projectionStarted(session))
        }
    }
    
    
    func startSession() async throws {
        try assertPhase(expected: .ready)
        
        // try await initializeHIDIO()
        try await initializeProjection()
    }
}
