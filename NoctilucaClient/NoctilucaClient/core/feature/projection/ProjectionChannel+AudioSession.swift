//
//  ProjectionChannel+Session.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/31/26.
//

import Foundation
import Combine

import SiriusKitClient

extension ProjectionChannel {
    // MARK: - Audio Session Event Handlers

    func handleAudioSessionCreatedEvent(_ event: AudioSessionCreatedEvent) async {
        self.logger.info("Audio session created: identifier=\(event.identifier), codec=\(event.codec.fourCC.stringRepresentation)")

        // Check if there's a pending continuation
        /*
        if let continuation = self.pendingAudioSessions[event.identifier] {
            self.pendingAudioSessions.removeValue(forKey: event.identifier)
            continuation(event)
            return
        }
         */

        // No pending request - auto-create session from server event
        guard let clientSession = self.clientSession else {
            self.logger.error("No client session available for audio session")
            return
        }

        guard let channel = await clientSession.channelManager.channels[event.identifier] as? ProjectionDataChannel else {
            self.logger.error("No ProjectionDataChannel found for audio session identifier: \(event.identifier)")
            return
        }

        let session = AudioProjectionSession(id: event.identifier, dataChannel: channel, controlChannel: self)

        do {
            try await session.prepare(codec: event.codec)
            try await session.start()

            // Set up data channel delegate
            channel.delegate = session

            self.audioSessions[event.identifier] = session
            self.logger.info("Audio projection session started: \(event.identifier)")
        } catch {
            self.logger.error("Failed to start audio projection session: \(error)")
        }
    }

    func handleAudioSessionEndedEvent(_ event: AudioSessionEndedEvent) async {
        self.logger.info("Audio session ended: identifier=\(event.identifier), reason=\(event.reason)")

        guard let session = self.audioSessions[event.identifier] else {
            self.logger.warning("No audio session found for identifier: \(event.identifier)")
            return
        }

        do {
            try session.stop()
        } catch {
            self.logger.error("Failed to stop audio session: \(error)")
        }

        self.audioSessions.removeValue(forKey: event.identifier)
    }
}
