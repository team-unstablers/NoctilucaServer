//
//  ProjectionChannel+AudioSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/31/26.
//

import Foundation

import SiriusKitClient

extension ProjectionChannel {
    // MARK: - Audio Session Event Handlers

    func handleAudioSessionCreationFailedEvent(_ event: AudioSessionCreationFailedEvent) async {
        self.logger.error("Audio session creation failed: identifier=\(event.identifier), reason=\(event.reason), message=\(event.message ?? "(nil)")")

        let error = ProjectionChannelError.audioSessionCreationFailed(
            identifier: event.identifier,
            reason: event.reason,
            message: event.message
        )
        _ = await state.failPendingAudioSessionRequest(event.identifier, error: error)
    }

    func handleAudioSessionCreatedEvent(_ event: AudioSessionCreatedEvent) async {
        self.logger.info("Audio session created: identifier=\(event.identifier), codec=\(event.codec.fourCC.stringRepresentation)")

        guard await state.hasPendingAudioSessionRequest(event.identifier) else {
            self.logger.warning("Ignoring unexpected AudioSessionCreatedEvent without pending request: identifier=\(event.identifier)")
            sendStopAudioProjectionRequest(identifier: event.identifier)
            return
        }

        guard let clientSession = self.clientSession else {
            self.logger.error("No client session available for audio session")
            _ = await state.failPendingAudioSessionRequest(event.identifier, error: ProjectionChannelError.channelClosed)
            return
        }

        guard let channel = await clientSession.channelManager.channels[event.identifier] as? ProjectionDataChannel else {
            self.logger.error("No ProjectionDataChannel found for audio session identifier: \(event.identifier)")
            _ = await state.failPendingAudioSessionRequest(event.identifier, error: ChannelError.invalidFrame)
            return
        }

        let audioProjectionPolicy = await SettingsStore.shared.settings.projection.audioProjectionPolicy
        let session = AudioProjectionSession(
            id: event.identifier,
            dataChannel: channel,
            controlChannel: self,
            audioJitterBufferPreset: audioProjectionPolicy.bufferPreset
        )

        // data channel 이벤트 consume 루프 설치
        await session.setup()

        do {
            try await session.prepare(codec: event.codec)
            try await session.start()

            await state.setAudioSession(event.identifier, session)
            self.logger.info("Audio projection session started: \(event.identifier)")

            continuation.yield(.audioSessionCreated(session))

            _ = await state.succeedPendingAudioSessionRequest(event.identifier, event: event)
        } catch {
            self.logger.error("Failed to start audio projection session: \(error)")

            do {
                try await session.stop()
            } catch {
                self.logger.warning("Failed to rollback audio session after start failure: \(error)")
            }

            _ = await state.failPendingAudioSessionRequest(
                event.identifier,
                error: ProjectionChannelError.audioSessionStartFailed(
                    identifier: event.identifier,
                    underlying: error
                )
            )
            sendStopAudioProjectionRequest(identifier: event.identifier)
        }
    }

    func handleAudioSessionEndedEvent(_ event: AudioSessionEndedEvent) async {
        self.logger.info("Audio session ended: identifier=\(event.identifier), reason=\(event.reason)")

        guard let session = await state.removeAudioSession(event.identifier) else {
            self.logger.warning("No audio session found for identifier: \(event.identifier)")
            return
        }

        do {
            try await session.stop()
        } catch {
            self.logger.error("Failed to stop audio session: \(error)")
        }

        continuation.yield(.audioSessionDestroyed(event.identifier, reason: event.reason, message: event.message))
    }
}
