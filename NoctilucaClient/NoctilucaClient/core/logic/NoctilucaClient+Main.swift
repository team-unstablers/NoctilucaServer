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
        
        self.logger.info("initializeHIDIO(): created HIDIOChannel")
        self.hidioChannel = channel
    }

    func initializeProjection() async throws {
        guard let channel = try await session.channelManager.openChannel(for: .projection, identifier: ChannelIdentifier()) as? ProjectionChannel else {
            // FIXME
            return
        }
        
        self.projectionChannel = channel
        self.logger.info("initializeProjection(): created ProjectionChannel")
        
        try await projectionChannel.subscribeCursorEvents()
        try await projectionChannel.updateDisplayLayout()
        _ = try await projectionChannel.subscribeDisplayChanges(eventMask: [.becamePrimary, .connected, .disconnected, .modified])
        
        
        /*
        let response = try await projectionChannel.requestWindowList()
        for window in response.windows {
            self.logger.info("initializeProjection(): window - id: \(window.windowID), title: \(window.windowTitle), owner: \(window.applicationName) (\(window.applicationBundleID))")
        }
         */
        
        // TODO: 이거 디스플레이 없는 컴퓨터에서 터지면 어쩌죠..?
        // let primaryDisplayID = await projectionChannel.displayLayoutManager.primaryDisplayID ?? -1
        
        // _ = try await channel.createSession(for: primaryDisplayID, projectionSettings: sessionSettings?.projection)
    }
    
    
    func startSession() async throws {
        try assertPhase(expected: .ready)
        
        try await initializeHIDIO()
        try await initializeProjection()
    }
}
