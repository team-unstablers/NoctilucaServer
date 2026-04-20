//
//  MockProjectionChannel.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

// MARK: - MockProjectionChannelState

/// 채널 본체가 Sendable 이므로 가변 상태를 actor 로 격리한다.
actor MockProjectionChannelState {
    private(set) var dataChannels: [UUID: ProjectionDataChannel] = [:]
    private(set) var videoSessions: [UUID: MockProjectionSession] = [:]
    private(set) var audioSessions: [UUID: MockAudioProjectionSession] = [:]

    func setDataChannel(_ channel: ProjectionDataChannel?, for identifier: UUID) {
        if let channel {
            dataChannels[identifier] = channel
        } else {
            dataChannels.removeValue(forKey: identifier)
        }
    }

    func removeDataChannel(for identifier: UUID) -> ProjectionDataChannel? {
        return dataChannels.removeValue(forKey: identifier)
    }

    func setVideoSession(_ session: MockProjectionSession?, for identifier: UUID) {
        if let session {
            videoSessions[identifier] = session
        } else {
            videoSessions.removeValue(forKey: identifier)
        }
    }

    func removeVideoSession(for identifier: UUID) -> MockProjectionSession? {
        return videoSessions.removeValue(forKey: identifier)
    }

    func setAudioSession(_ session: MockAudioProjectionSession?, for identifier: UUID) {
        if let session {
            audioSessions[identifier] = session
        } else {
            audioSessions.removeValue(forKey: identifier)
        }
    }

    func removeAudioSession(for identifier: UUID) -> MockAudioProjectionSession? {
        return audioSessions.removeValue(forKey: identifier)
    }

    func snapshotAndClear() -> (
        dataChannels: [ProjectionDataChannel],
        videoSessions: [MockProjectionSession],
        audioSessions: [MockAudioProjectionSession]
    ) {
        let result = (
            dataChannels: Array(dataChannels.values),
            videoSessions: Array(videoSessions.values),
            audioSessions: Array(audioSessions.values)
        )
        dataChannels.removeAll()
        videoSessions.removeAll()
        audioSessions.removeAll()
        return result
    }
}

// MARK: - MockProjectionChannel

/// NoctilucaServer의 ProjectionChannel을 간소화한 Mock 구현.
/// - H.265 비디오 고정, Opus 오디오 고정
/// - CodecNegotiator, AutoQualityPlanner, DisplayLayoutManager 등 제거
final class MockProjectionChannel: Channel, ChannelEventConsumer {
    private let logger = SiriusLogger(category: "MockProjectionChannel", subsystem: "app.noctiluca.mockserver")

    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .userInput

    let projectionSource: URL
    let state = MockProjectionChannelState()

    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<MockProjectionChannel>!

    init(handle: ChannelHandle, projectionSource: URL) {
        self.handle = handle
        self.projectionSource = projectionSource
        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    /// Channel 프로토콜 요구를 만족시키기 위한 init. MockServer에서는 사용하지 않는다.
    convenience init(handle: ChannelHandle) {
        fatalError("Use init(handle:projectionSource:) instead")
    }

    func destroy() async {
        let snapshot = await state.snapshotAndClear()

        for session in snapshot.videoSessions {
            await session.stop()
        }

        for session in snapshot.audioSessions {
            await session.stop()
        }

        for channel in snapshot.dataChannels {
            await channel.state.setDelegate(nil)
            do {
                try await channel.handle.close()
            } catch {
                logger.warning("Failed to close data channel during destroy: \(error)")
            }
        }
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
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
            try await handle.send(opcode: .unsubscribeDisplayChangesResponse, message: UnsubscribeDisplayChangesResponse(
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

    func handleError(error: any Error) async {
        await destroy()
    }

    func handleStreamClose() async {
        await destroy()
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
            options: request.preferredCodecs.first!.options,
            quality: .auto(mode: .balancedPriority)
        )

        do {
            let openedChannel = try await session.channelManager.openChannel(
                for: .projectionData,
                identifier: identifier
            ) as! ProjectionDataChannel

            await openedChannel.state.setDelegate(self)
            await state.setDataChannel(openedChannel, for: identifier)

            let projectionSession = MockProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                sourceURL: projectionSource,
                codec: codec
            )
            await state.setVideoSession(projectionSession, for: identifier)

            try await projectionSession.prepare()
            try await projectionSession.start()

            try await handle.send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: codec
            ))

            logger.info("Video projection session \(identifier) started")
        } catch {
            logger.error("Failed to handle projection request \(identifier): \(error)")

            // 클린업
            if let session = await state.removeVideoSession(for: identifier) {
                await session.stop()
            }
            if let channel = await state.removeDataChannel(for: identifier) {
                await channel.state.setDelegate(nil)
                try? await channel.handle.close()
            }
        }
    }

    private func handleStopProjectionRequest(_ request: StopProjectionRequest) async {
        let identifier = request.identifier
        logger.info("Stopping video projection session \(identifier)")

        if let session = await state.removeVideoSession(for: identifier) {
            await session.stop()
        }
        if let channel = await state.removeDataChannel(for: identifier) {
            await channel.state.setDelegate(nil)
            try? await channel.handle.close()
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

            await openedChannel.state.setDelegate(self)
            await state.setDataChannel(openedChannel, for: identifier)

            let audioSession = MockAudioProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                sourceURL: projectionSource,
                codec: codec
            )
            await state.setAudioSession(audioSession, for: identifier)

            try await audioSession.prepare()
            try await audioSession.start()

            try await handle.send(opcode: .audioSessionCreatedEvent, message: AudioSessionCreatedEvent(
                identifier: identifier,
                source: request.source,
                codec: codec
            ))

            logger.info("Audio projection session \(identifier) started")
        } catch {
            logger.error("Failed to handle audio projection request \(identifier): \(error)")

            if let session = await state.removeAudioSession(for: identifier) {
                await session.stop()
            }
            if let channel = await state.removeDataChannel(for: identifier) {
                await channel.state.setDelegate(nil)
                try? await channel.handle.close()
            }
        }
    }

    private func handleStopAudioProjectionRequest(_ request: StopAudioProjectionRequest) async {
        let identifier = request.identifier
        logger.info("Stopping audio projection session \(identifier)")

        if let session = await state.removeAudioSession(for: identifier) {
            await session.stop()
        }
        if let channel = await state.removeDataChannel(for: identifier) {
            await channel.state.setDelegate(nil)
            try? await channel.handle.close()
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
            rotation: .deg0,
            supportedSpecs: [],
            thumbnail: nil,
            metadata: [:],
            flags: 0,
            virtualDisplayIdentifier: nil
        )

        try await handle.send(opcode: .displayListResponse, message: DisplayListResponse(
            requestID: request.requestID,
            displays: [mockDisplay]
        ))
    }

    /// 디스플레이 변경 구독 — 더미 구독 ID 반환 (실제 이벤트는 발생하지 않음)
    private func handleSubscribeDisplayChangesRequest(_ request: SubscribeDisplayChangesRequest) async throws {
        try await handle.send(opcode: .subscribeDisplayChangesResponse, message: SubscribeDisplayChangesResponse(
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

            if let session = await self.state.removeVideoSession(for: identifier) {
                await session.stop()
            }
            if let session = await self.state.removeAudioSession(for: identifier) {
                await session.stop()
            }
            _ = await self.state.removeDataChannel(for: identifier)
        }
    }

    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error) {
        Task { [weak self] in
            guard let self else { return }
            self.logger.warning("ProjectionDataChannel \(channel.identifier) error: \(error)")

            let identifier = channel.identifier
            if let session = await self.state.removeVideoSession(for: identifier) {
                await session.stop()
            }
            if let session = await self.state.removeAudioSession(for: identifier) {
                await session.stop()
            }
            _ = await self.state.removeDataChannel(for: identifier)
        }
    }
}
