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
    private func requestSession(identifier: UUID, displayID: Int32, preferredCodecs: [Codec]) async throws -> ProjectionSessionCreatedEvent {
        
        let response = try await self.sendSessionRequest(
            sessionID: identifier,
            opcode: .projectionRequest,
            message: ProjectionRequest(
                identifier: identifier,
                viewport: ProjectionSource(
                    value: .entireDisplay(EntireDisplayProjectionSource(displayID: displayID)),
                    flags: []
                ),
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


    func createSession(for displayID: Int = -1, projectionSettings: SessionSettings.Projection?) async throws -> ProjectionSession {
        guard let clientSession = self.clientSession else {
            fatalError()
        }

        let identifier = UUID()

        let preferredCodecs = buildPreferredCodecs(from: projectionSettings)
        let response = try await requestSession(identifier: identifier, displayID: Int32(displayID), preferredCodecs: preferredCodecs)

        let channel = await clientSession.channelManager.channels[identifier] as! ProjectionDataChannel

        let session = await ProjectionSession(id: identifier, displayID: Int(displayID), dataChannel: channel, controlChannel: self)

        try await session.prepare(codec: response.codec)
        try await session.start()

        self.sessions[identifier] = session
        
        defer {
            Task { @MainActor in
                self.events.send(.sessionCreated(session))
            }
        }
        
        return session
    }
    
    // TODO: AudioProjectionSession을 반환해야 함
    func createAudioSession(for source: AudioSource, projectionSettings: SessionSettings.Projection?) async throws {
        do {
            let audioSpecs = projectionSettings?.audioCodecSpecifications ?? [.opus]
            let preferredCodecs = audioSpecs.map { $0.toSiriusKitCodec() }
            
            // TODO: 성공 여부를 감시해야 함
            // 단순히 send() 하는 것만으론 부족하다!
            try await self.send(opcode: .audioProjectionRequest, message: AudioProjectionRequest(
                identifier: UUID(),
                source: source,
                preferredCodecs: preferredCodecs
            ))
            self.logger.info("Sent AudioProjectionRequest")
        } catch {
            self.logger.error("Failed to send AudioProjectionRequest: \(error)")
            // 오디오 요청 실패는 비디오 세션에 영향을 주지 않도록 무시
        }
    }
    
    /// 모든 projection session을 중지하고 리소스를 정리합니다.
    func stopAllSessions() async {
        // 모든 비디오 세션 중지
        for (_, session) in sessions {
            do {
                try await session.stop()
            } catch {
                logger.warning("Failed to stop projection session: \(error)")
            }
        }
        sessions.removeAll()

        // 모든 오디오 세션 중지
        for (_, session) in audioSessions {
            do {
                try session.stop()
            } catch {
                logger.warning("Failed to stop audio projection session: \(error)")
            }
        }
        audioSessions.removeAll()
    }
}
