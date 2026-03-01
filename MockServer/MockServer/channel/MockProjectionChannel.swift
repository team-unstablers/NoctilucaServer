//
//  MockProjectionChannel.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

/// NoctilucaServer의 ProjectionChannel을 간소화한 Mock 구현.
/// - H.265 비디오 고정, Opus 오디오 고정
/// - CodecNegotiator, AutoQualityPlanner, DisplayLayoutManager 등 제거
class MockProjectionChannel: Channel {
    private let logger = SiriusLogger(category: "MockProjectionChannel", subsystem: "app.noctiluca.mockserver")

    override var serviceClass: ServiceClass { .userInput }

    let projectionSource: URL

    // identifier -> session/channel tracking
    private var dataChannels: [UUID: ProjectionDataChannel] = [:]
    private var videoSessions: [UUID: MockProjectionSession] = [:]
    private var audioSessions: [UUID: MockAudioProjectionSession] = [:]

    init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection, projectionSource: URL) {
        self.projectionSource = projectionSource
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        fatalError("Use init(using:identifier:direction:projectionSource:) instead")
    }

    func destroy() async {
        // 모든 비디오 세션 정지
        for (_, session) in videoSessions {
            await session.stop()
        }
        videoSessions.removeAll()

        // 모든 오디오 세션 정지
        for (_, session) in audioSessions {
            await session.stop()
        }
        audioSessions.removeAll()

        // 모든 데이터 채널 닫기
        for (_, channel) in dataChannels {
            channel.projectionDelegate = nil
            do {
                try await channel.close()
            } catch {
                logger.warning("Failed to close data channel during destroy: \(error)")
            }
        }
        dataChannels.removeAll()
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .projectionRequest:
            let request = try ProjectionRequest.fromProtobufBytes(frame.data)
            await handleProjectionRequest(request)

        case .stopProjectionRequest:
            let request = try StopProjectionRequest.fromProtobufBytes(frame.data)
            await handleStopProjectionRequest(request)

        case .audioProjectionRequest:
            let request = try AudioProjectionRequest.fromProtobufBytes(frame.data)
            await handleAudioProjectionRequest(request)

        case .stopAudioProjectionRequest:
            let request = try StopAudioProjectionRequest.fromProtobufBytes(frame.data)
            await handleStopAudioProjectionRequest(request)

        case .projectionPerformanceReport:
            // 품질 플래너가 없으므로 무시
            break

        case .displayListRequest:
            let request = try DisplayListRequest.fromProtobufBytes(frame.data)
            try await handleDisplayListRequest(request)

        case .subscribeDisplayChangesRequest:
            let request = try SubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await handleSubscribeDisplayChangesRequest(request)

        case .unsubscribeDisplayChangesRequest:
            // 구독 해제 — 더미 성공 응답
            let request = try UnsubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await send(opcode: .unsubscribeDisplayChangesResponse, message: UnsubscribeDisplayChangesResponse(
                requestID: request.requestID,
                subscriptionID: request.subscriptionID,
                isSuccess: true
            ))

        case .subscribeCursorEventsRequest,
             .unsubscribeCursorEventsRequest:
            // Mock에서는 지원하지 않음 — 무시
            logger.trace("Ignoring unsupported opcode: \(frame.opcode)")

        default:
            logger.warning("Unhandled opcode in MockProjectionChannel: \(frame.opcode)")
        }
    }

    // MARK: - Video Projection

    private func handleProjectionRequest(_ request: ProjectionRequest) async {
        guard let session = clientSession else { return }

        let identifier = request.identifier

        // H.265 고정 코덱
        let codec = Codec(
            fourCC: .avc1,
            frameRate: 60.0,
            size: SRSize(width: 1920, height: 1080),
            options: CodecOptions(),
            quality: .auto(mode: .balancedPriority)
        )

        do {
            let openedChannel = try await session.channelManager.openChannel(
                for: .projectionData,
                identifier: identifier
            ) as! ProjectionDataChannel

            openedChannel.projectionDelegate = self
            dataChannels[identifier] = openedChannel

            let projectionSession = MockProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                sourceURL: projectionSource,
                codec: codec
            )
            videoSessions[identifier] = projectionSession

            try await projectionSession.prepare()
            try await projectionSession.start()

            try await send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: codec
            ))

            logger.info("Video projection session \(identifier) started")
        } catch {
            logger.error("Failed to handle projection request \(identifier): \(error)")

            // 클린업
            if let session = videoSessions.removeValue(forKey: identifier) {
                await session.stop()
            }
            if let channel = dataChannels.removeValue(forKey: identifier) {
                channel.projectionDelegate = nil
                try? await channel.close()
            }
        }
    }

    private func handleStopProjectionRequest(_ request: StopProjectionRequest) async {
        let identifier = request.identifier
        logger.info("Stopping video projection session \(identifier)")

        if let session = videoSessions.removeValue(forKey: identifier) {
            await session.stop()
        }
        if let channel = dataChannels.removeValue(forKey: identifier) {
            channel.projectionDelegate = nil
            try? await channel.close()
        }
    }

    // MARK: - Audio Projection

    private func handleAudioProjectionRequest(_ request: AudioProjectionRequest) async {
        guard let session = clientSession else { return }

        let identifier = request.identifier

        // Opus 고정 코덱
        let codec = AudioCodec(
            fourCC: .opus,
            quality: .auto,
            sampleRate: 48000,
            channelCount: 2
        )

        do {
            let openedChannel = try await session.channelManager.openChannel(
                for: .projectionData,
                identifier: identifier
            ) as! ProjectionDataChannel

            openedChannel.projectionDelegate = self
            dataChannels[identifier] = openedChannel

            let audioSession = MockAudioProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                sourceURL: projectionSource,
                codec: codec
            )
            audioSessions[identifier] = audioSession

            try await audioSession.prepare()
            try await audioSession.start()

            try await send(opcode: .audioSessionCreatedEvent, message: AudioSessionCreatedEvent(
                identifier: identifier,
                source: request.source,
                codec: codec
            ))

            logger.info("Audio projection session \(identifier) started")
        } catch {
            logger.error("Failed to handle audio projection request \(identifier): \(error)")

            if let session = audioSessions.removeValue(forKey: identifier) {
                await session.stop()
            }
            if let channel = dataChannels.removeValue(forKey: identifier) {
                channel.projectionDelegate = nil
                try? await channel.close()
            }
        }
    }

    private func handleStopAudioProjectionRequest(_ request: StopAudioProjectionRequest) async {
        let identifier = request.identifier
        logger.info("Stopping audio projection session \(identifier)")

        if let session = audioSessions.removeValue(forKey: identifier) {
            await session.stop()
        }
        if let channel = dataChannels.removeValue(forKey: identifier) {
            channel.projectionDelegate = nil
            try? await channel.close()
        }
    }

    // MARK: - Display Management

    /// 가상 디스플레이 1개 (1920x1080, 60Hz)를 반환한다.
    private func handleDisplayListRequest(_ request: DisplayListRequest) async throws {
        let mockDisplay = DisplayInfo(
            displayID: 1,
            kind: .internal,
            displayName: "MockServer Virtual Display",
            state: DisplayState(isPrimary: true, isConnected: true, isActive: true),
            bounds: SRRect(x: 0, y: 0, width: 1920, height: 1080),
            refreshRate: 60.0,
            colorDepth: .bit8,
            dynamicRange: .sdr,
            colorProfile: .sRGB,
            physicalSizeInfo: nil,
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        )

        try await send(opcode: .displayListResponse, message: DisplayListResponse(
            requestID: request.requestID,
            displays: [mockDisplay]
        ))
    }

    /// 디스플레이 변경 구독 — 더미 구독 ID 반환 (실제 이벤트는 발생하지 않음)
    private func handleSubscribeDisplayChangesRequest(_ request: SubscribeDisplayChangesRequest) async throws {
        try await send(opcode: .subscribeDisplayChangesResponse, message: SubscribeDisplayChangesResponse(
            requestID: request.requestID,
            subscriptionID: UUID()
        ))
    }
}

// MARK: - ProjectionDataChannelDelegate

extension MockProjectionChannel: ProjectionDataChannelDelegate {
    func projectionDataChannelDidClose(_ channel: ProjectionDataChannel) {
        Task { [weak self] in
            guard let self else { return }
            let identifier = channel.identifier

            if let session = videoSessions.removeValue(forKey: identifier) {
                await session.stop()
            }
            if let session = audioSessions.removeValue(forKey: identifier) {
                await session.stop()
            }
            dataChannels.removeValue(forKey: identifier)
        }
    }

    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error) {
        Task { [weak self] in
            guard let self else { return }
            logger.warning("ProjectionDataChannel \(channel.identifier) error: \(error)")

            let identifier = channel.identifier
            if let session = videoSessions.removeValue(forKey: identifier) {
                await session.stop()
            }
            if let session = audioSessions.removeValue(forKey: identifier) {
                await session.stop()
            }
            dataChannels.removeValue(forKey: identifier)
        }
    }
}
