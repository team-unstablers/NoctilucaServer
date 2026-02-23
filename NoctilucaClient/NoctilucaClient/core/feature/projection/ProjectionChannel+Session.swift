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

    /// 프로젝션 세션 생성 요청을 보냅니다.
    private func requestSession(identifier: UUID, source: ProjectionSourceDescriptor, preferredCodecs: [Codec]) async throws -> ProjectionSessionCreatedEvent {

        let response = try await self.sendSessionRequest(
            sessionID: identifier,
            opcode: .projectionRequest,
            message: ProjectionRequest(
                identifier: identifier,
                viewport: source.toProjectionSource(),
                preferredCodecs: preferredCodecs
            ),
        ) as ProjectionSessionCreatedEvent

        return response
    }

    private func buildPreferredCodecs(from projectionSettings: SessionSettings.Projection?) -> [Codec] {
        guard let projectionSettings else {
            return CodecSpecification.defaultSpecifications.map { $0.toSiriusKitCodec() }
        }

        switch projectionSettings.codecSettingsMode {
        case .useDefault:
            return CodecSpecification.defaultSpecifications.map { $0.toSiriusKitCodec() }
        case .manual:
            let specifications = projectionSettings.codecSpecifications
            guard !specifications.isEmpty else {
                logger.warning("Projection codec specifications are empty; sending empty preferredCodecs.")
                return []
            }

            let codecs = specifications.map { $0.toSiriusKitCodec() }
            return applyNegotiationPolicy(projectionSettings.codecNegotiationPolicy, to: codecs)
        }
    }

    private func applyNegotiationPolicy(_ policy: SessionSettings.CodecNegotiationPolicy, to codecs: [Codec]) -> [Codec] {
        let shouldForceMandatory = policy == .asMandatory

        return codecs.map { codec in
            let options = remapOptions(codec.options, mandatory: shouldForceMandatory)
            return Codec(
                fourCC: codec.fourCC,
                frameRate: codec.frameRate,
                size: codec.size,
                options: options,
                quality: codec.quality
            )
        }
    }

    private func remapOptions(_ options: CodecOptions, mandatory: Bool) -> CodecOptions {
        var combined = options.mandatory
        combined.merge(options.optional, uniquingKeysWith: { _, new in new })

        if mandatory {
            return CodecOptions(mandatory: combined, optional: [:])
        }

        return CodecOptions(mandatory: [:], optional: combined)
    }

    private func requestAudioSession(
        identifier: UUID,
        source: AudioSource,
        preferredCodecs: [SiriusKitClient.AudioCodec],
        timeout: TimeInterval = 5.0
    ) async throws -> AudioSessionCreatedEvent {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<AudioSessionCreatedEvent, Error>) in
            guard let self else {
                continuation.resume(throwing: ProjectionChannelError.channelClosed)
                return
            }

            Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ProjectionChannelError.channelClosed)
                    return
                }

                await self.registerPendingAudioSessionRequest(
                    identifier: identifier,
                    timeout: timeout,
                    continuation: continuation
                )

                do {
                    try await self.send(opcode: .audioProjectionRequest, message: AudioProjectionRequest(
                        identifier: identifier,
                        source: source,
                        preferredCodecs: preferredCodecs
                    ))
                    self.logger.info("Sent AudioProjectionRequest: identifier=\(identifier)")
                } catch {
                    self.logger.error("Failed to send AudioProjectionRequest: \(error)")
                    _ = await self.state.failPendingAudioSessionRequest(identifier, error: error)
                }
            }
        }
    }


    func createSession(for source: ProjectionSourceDescriptor, projectionSettings: SessionSettings.Projection?) async throws -> ProjectionSession {
        guard let clientSession = self.clientSession else {
            fatalError()
        }

        let identifier = UUID()

        let preferredCodecs = buildPreferredCodecs(from: projectionSettings)
        let response = try await requestSession(identifier: identifier, source: source, preferredCodecs: preferredCodecs)

        let channel = await clientSession.channelManager.channels[identifier] as! ProjectionDataChannel

        let projectionAppSettings = SettingsStore.shared.settings.projection
        let enableJitterBuffer = projectionAppSettings.enableJitterBuffer
        let jitterBufferPreset = projectionAppSettings.jitterBufferPreset
        let session = await ProjectionSession(id: identifier, sourceDescriptor: source, dataChannel: channel, controlChannel: self, enableJitterBuffer: enableJitterBuffer, jitterBufferPreset: jitterBufferPreset)

        try await session.prepare(codec: response.codec)
        try await session.start()

        await state.setSession(identifier, session)

        defer {
            Task { @MainActor in
                self.events.send(.sessionCreated(session))
            }
        }

        return session
    }

    // TODO: AudioProjectionSession을 반환해야 함
    func createAudioSession(for source: AudioSource, projectionSettings: SessionSettings.Projection?) async throws {
        let audioSpecs = projectionSettings?.audioCodecSpecifications ?? [.opus]
        let preferredCodecs = audioSpecs.map { $0.toSiriusKitCodec() }

        let maxAttempts = 2
        let retryBackoffNanoseconds: UInt64 = 300_000_000

        for attempt in 1...maxAttempts {
            let identifier = UUID()

            do {
                _ = try await requestAudioSession(
                    identifier: identifier,
                    source: source,
                    preferredCodecs: preferredCodecs
                )
                self.logger.info("Audio projection request succeeded: identifier=\(identifier), attempt=\(attempt)")
                return
            } catch {
                if error is CancellationError {
                    throw error
                }

                let shouldRetry: Bool
                if let projectionError = error as? ProjectionChannelError {
                    shouldRetry = projectionError.isRetryableAudioSessionCreationFailure
                } else {
                    shouldRetry = true
                }

                guard attempt < maxAttempts, shouldRetry else {
                    throw error
                }

                self.logger.warning("Audio projection request failed (attempt \(attempt)): \(error.localizedDescription). Retrying...")
                try await Task.sleep(nanoseconds: retryBackoffNanoseconds)
            }
        }

        throw ProjectionChannelError.sessionCreationCancelled
    }

    /// 모든 projection session을 중지하고 리소스를 정리합니다.
    func stopAllSessions() async {
        await state.cancelAllPendingAudioSessionRequests()

        // 모든 비디오 세션 중지
        let allSessions = await state.removeAllSessions()
        for session in allSessions {
            do {
                try await session.stop()
            } catch {
                logger.warning("Failed to stop projection session: \(error)")
            }
        }

        // 모든 오디오 세션 중지
        let allAudioSessions = await state.removeAllAudioSessions()
        for session in allAudioSessions {
            do {
                try session.stop()
            } catch {
                logger.warning("Failed to stop audio projection session: \(error)")
            }
        }
    }

    // MARK: - Server-initiated session events

    func handleProjectionSessionEndedEvent(_ event: ProjectionSessionEndedEvent) async {
        guard let identifier = event.identifier else {
            logger.warning("Received ProjectionSessionEndedEvent without identifier")
            return
        }

        logger.info("Projection session ended: identifier=\(identifier), reason=\(event.reason)")

        guard let session = await state.removeSession(identifier) else {
            logger.warning("No projection session found for identifier: \(identifier)")
            return
        }

        do {
            try await session.stop()
        } catch {
            logger.error("Failed to stop projection session \(identifier): \(error)")
        }

        Task { @MainActor in
            self.events.send(.sessionDestroyed(identifier, reason: event.message ?? "reason=\(event.reason)"))
        }
    }

    func handleProjectionSessionChangedEvent(_ event: ProjectionSessionChangedEvent) async {
        guard let identifier = event.identifier else {
            logger.warning("Received ProjectionSessionChangedEvent without identifier")
            return
        }

        logger.info("Projection session changed: identifier=\(identifier), reason=\(event.reason)")

        guard let session = await state.getSession(identifier) else {
            logger.warning("No projection session found for identifier: \(identifier)")
            return
        }

        // 코덱 변경 시 디코더 재구성
        if let newCodec = event.codec {
            logger.info("Reconfiguring decoder for session \(identifier) with new codec: \(newCodec.fourCC)")
            do {
                try await session.reconfigure(codec: newCodec)
            } catch {
                logger.error("Failed to reconfigure session \(identifier): \(error)")
            }
        }
    }
}
