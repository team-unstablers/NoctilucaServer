//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Combine
import Atomics

import CoreGraphics

import SiriusKitClient

enum ProjectionChannelError: Error {
    case sessionCreationCancelled
    case channelClosed
}

class ProjectionChannel: Channel, ObservableObject {
    let logger = SiriusLogger(category: "ProjectionChannel", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    private static let defaultSpecifications: [CodecSpecification] = [.hevc, .h264]

    /// Request ID 생성을 위한 atomic 카운터
    private let requestCounter = ManagedAtomic<UInt64>(0)

    /// 다음 request ID를 생성합니다.
    func nextRequestID() -> UInt64 {
        requestCounter.loadThenWrappingIncrement(ordering: .relaxed)
    }

    private(set) var pendingSessions: [UUID: (ProjectionSessionCreatedEvent) -> Void] = [:]
    private(set) var sessions: [UUID: ProjectionSession] = [:]

    // MARK: - Audio Sessions

    private(set) var pendingAudioSessions: [UUID: (AudioSessionCreatedEvent) -> Void] = [:]
    private(set) var audioSessions: [UUID: AudioProjectionSession] = [:]

    /// 모든 projection session을 중지하고 리소스를 정리합니다.
    func stopAllSessions() async {
        // 디스플레이 변경 구독 취소
        displayChangeCancellable?.cancel()
        displayChangeCancellable = nil

        // 모든 비디오 세션 중지
        for (_, session) in sessions {
            do {
                try await session.stop()
            } catch {
                logger.warning("Failed to stop projection session: \(error)")
            }
        }
        sessions.removeAll()
        pendingSessions.removeAll()

        // 모든 오디오 세션 중지
        for (_, session) in audioSessions {
            do {
                try session.stop()
            } catch {
                logger.warning("Failed to stop audio projection session: \(error)")
            }
        }
        audioSessions.removeAll()
        pendingAudioSessions.removeAll()
    }

    deinit {
        displayChangeCancellable?.cancel()
    }

    // MARK: - Displayman

    var pendingDisplayListRequests: [UInt64: (DisplayListResponse) -> Void] = [:]
    var pendingSubscribeDisplayChangesRequests: [UInt64: (SubscribeDisplayChangesResponse) -> Void] = [:]
    var displayChangesSubscriptionID: UUID? = nil

    /// 현재 프로젝션 대상 디스플레이 ID
    private(set) var currentDisplayID: Int32 = -1

    /// 현재 프로젝션 설정 (재시작 시 사용)
    private var currentProjectionSettings: SessionSettings.Projection? = nil

    let displayChangeSubject = PassthroughSubject<DisplayChangedEvent, Never>()
    private var displayChangeCancellable: AnyCancellable?

    @Published
    private(set) var cursorImage: CGImage? = nil
    
    @Published
    private(set) var cursorHotspot: CGPoint? = nil
    
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)

        assert(direction == .local, "ProjectionChannel must be opened from client side")

        setupDisplayChangeHandler()
    }

    // MARK: - Display Change Debouncing

    private func setupDisplayChangeHandler() {
        displayChangeCancellable = displayChangeSubject
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] event in
                Task { await self?.handleDebouncedDisplayChange(event) }
            }
    }

    private func handleDebouncedDisplayChange(_ event: DisplayChangedEvent) async {
        // 메인 디스플레이 관련 변경만 처리
        let shouldRestartProjection = event.eventType.contains(.becamePrimary)
            || (event.eventType.contains(.disconnected) && event.display.state.isPrimary)
            || (event.eventType.contains(.modified) && event.display.state.isPrimary)

        guard shouldRestartProjection else {
            self.logger.info("Display change event does not require projection restart")
            return
        }

        self.logger.info("Main display changed, restarting projection...")

        // 기존 세션 중지
        for (_, session) in self.sessions {
            do {
                try await session.stop()
            } catch {
                self.logger.error("Failed to stop existing projection session: \(error)")
            }
        }
        self.sessions.removeAll()

        // 새로운 디스플레이 정보 조회 및 프로젝션 재시작
        do {
            let _ = try await self.createSession(projectionSettings: self.currentProjectionSettings)
        } catch {
            self.logger.error("Failed to restart projection session: \(error)")
        }
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        switch frame.opcode {
        case .projectionSessionCreatedEvent:
            let event = try ProjectionSessionCreatedEvent.fromProtobufBytes(frame.data)
            self.logger.info("Received ProjectionSessionCreatedEvent: sessionId=\(event.identifier)")
            
            if let continuation = self.pendingSessions[event.identifier] {
                continuation(event)
            } else {
                self.logger.warning("No pending session found for identifier: \(event.identifier)")
            }
            
        case .cursorEvent:
            let event = try CursorEvent.fromProtobufBytes(frame.data)
            try await self.handleCursorEvent(event)

        // MARK: - Displayman opcodes

        case .displayListResponse:
            let response = try DisplayListResponse.fromProtobufBytes(frame.data)
            self.handleDisplayListResponse(response)

        case .subscribeDisplayChangesResponse:
            let response = try SubscribeDisplayChangesResponse.fromProtobufBytes(frame.data)
            self.handleSubscribeDisplayChangesResponse(response)

        case .displayChangedEvent:
            let event = try DisplayChangedEvent.fromProtobufBytes(frame.data)
            self.handleDisplayChangedEvent(event)

        // MARK: - Audio projection opcodes

        case .audioSessionCreatedEvent:
            let event = try AudioSessionCreatedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionCreatedEvent(event)

        case .audioSessionCreationFailedEvent:
            let event = try AudioSessionCreationFailedEvent.fromProtobufBytes(frame.data)
            self.logger.error("Audio session creation failed: identifier=\(event.identifier), reason=\(event.reason)")

        case .audioSessionEndedEvent:
            let event = try AudioSessionEndedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionEndedEvent(event)

        default:
            break
        }
    }
    
    func createSession(projectionSettings: SessionSettings.Projection?) async throws -> ProjectionSession {
        guard let clientSession = self.clientSession else {
            fatalError()
        }

        // 프로젝션 설정 저장 (재시작 시 사용)
        self.currentProjectionSettings = projectionSettings

        let identifier = UUID()

        // 디스플레이 목록 조회 및 메인 디스플레이 찾기
        let displayID = try await fetchPrimaryDisplayID()
        self.currentDisplayID = displayID

        let preferredCodecs = buildPreferredCodecs(from: projectionSettings)
        try await sendProjectionRequest(identifier: identifier, displayID: displayID, preferredCodecs: preferredCodecs)

        let createdEvent = await withCheckedContinuation { cont in
            self.pendingSessions[identifier] = { event in
                self.pendingSessions.removeValue(forKey: identifier)
                cont.resume(returning: event)
            }
        }

        let channel = clientSession.channelManager.channels[identifier] as! ProjectionDataChannel

        let session = ProjectionSession(id: identifier, dataChannel: channel, controlChannel: self)

        try await session.prepare(codec: createdEvent.codec)
        try await session.start()

        self.sessions[identifier] = session

        // 디스플레이 변경 이벤트 구독
        do {
            let _ = try await subscribeDisplayChanges(eventMask: [.becamePrimary, .connected, .disconnected, .modified])
            self.logger.info("Subscribed to display change events")
        } catch {
            self.logger.warning("Failed to subscribe to display change events: \(error)")
        }
        
        // 오디오 프로젝션 요청
        if self.currentProjectionSettings?.isAudioProjectionEnabled ?? true {
            do {
                let audioSpecs = self.currentProjectionSettings?.audioCodecSpecifications ?? [.opus]
                let preferredCodecs = audioSpecs.map { $0.toSiriusKitCodec() }
                
                try await self.send(opcode: .audioProjectionRequest, message: AudioProjectionRequest(
                    identifier: UUID(),
                    source: .sessionAudio,
                    preferredCodecs: preferredCodecs
                ))
                self.logger.info("Sent AudioProjectionRequest")
            } catch {
                self.logger.error("Failed to send AudioProjectionRequest: \(error)")
                // 오디오 요청 실패는 비디오 세션에 영향을 주지 않도록 무시
            }
        } else {
            self.logger.info("Audio projection is disabled in settings, skipping request.")
        }

        return session
    }

    /// 서버에서 디스플레이 목록을 조회하고 메인 디스플레이 ID를 반환합니다.
    private func fetchPrimaryDisplayID() async throws -> Int32 {
        let response = try await requestDisplayList()

        // 메인 디스플레이 찾기
        if let primaryDisplay = response.displays.first(where: { $0.state.isPrimary }) {
            self.logger.info("Found primary display: id=\(primaryDisplay.displayID), name=\(primaryDisplay.displayName)")
            return Int32(primaryDisplay.displayID)
        }

        // 메인 디스플레이가 없으면 첫 번째 연결된 디스플레이 사용
        if let firstDisplay = response.displays.first(where: { $0.state.isConnected }) {
            self.logger.warning("No primary display found, using first connected display: id=\(firstDisplay.displayID)")
            return Int32(firstDisplay.displayID)
        }

        // 아무 디스플레이도 없으면 -1 반환 (서버가 기본 처리)
        self.logger.warning("No displays found, using default display ID -1")
        return -1
    }

    private func sendProjectionRequest(identifier: UUID, displayID: Int32, preferredCodecs: [Codec]) async throws {
        try await self.send(opcode: .projectionRequest, message: ProjectionRequest(
            identifier: identifier,
            viewport: ProjectionSource(
                value: .entireDisplay(EntireDisplayProjectionSource(displayID: displayID)),
                flags: []
            ),
            preferredCodecs: preferredCodecs
        ))
    }

    private func buildPreferredCodecs(from projectionSettings: SessionSettings.Projection?) -> [Codec] {
        guard let projectionSettings else {
            return Self.defaultSpecifications.map { $0.toSiriusKitCodec() }
        }

        switch projectionSettings.codecSettingsMode {
        case .useDefault:
            return Self.defaultSpecifications.map { $0.toSiriusKitCodec() }
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
    
    func subscribeCursorEvents() async throws {
        try await self.send(opcode: .subscribeCursorEventsRequest, message: SubscribeCursorEventsRequest(
            // FIXME
            requestID: 0,
            flags: 0
        ))
    }
    
    func unsubscribeCursorEvents() async throws {
        try await self.send(opcode: .unsubscribeCursorEventsRequest, message: UnsubscribeCursorEventsRequest(
            // FIXME
            requestID: 0,
            subscriptionID: UUID()
        ))
    }
    
    private func handleCursorEvent(_ event: CursorEvent) async throws {
        switch event.event {
        case .imageEvent(let imageEvent):
            try await handleCursorImageEvent(imageEvent)
        case .moveEvent(let moveEvent):
            logger.warning("WARN: Cursor move event received: newPosition=\(moveEvent.position.cgPoint)")
        default:
            break
        }
        
    }
    
    private func handleCursorImageEvent(_ event: CursorImageEvent) async throws {
        guard let data = event.imageData,
              let dataProvider = CGDataProvider(data: data as CFData)
        else {
            return
        }

        let cursorImage = CGImage(
            pngDataProviderSource: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )

        await MainActor.run {
            self.cursorImage = cursorImage
            self.cursorHotspot = event.hotspot.cgPoint
        }
    }

    // MARK: - Audio Session Event Handlers

    private func handleAudioSessionCreatedEvent(_ event: AudioSessionCreatedEvent) async {
        self.logger.info("Audio session created: identifier=\(event.identifier), codec=\(event.codec.fourCC.stringRepresentation)")

        // Check if there's a pending continuation
        if let continuation = self.pendingAudioSessions[event.identifier] {
            self.pendingAudioSessions.removeValue(forKey: event.identifier)
            continuation(event)
            return
        }

        // No pending request - auto-create session from server event
        guard let clientSession = self.clientSession else {
            self.logger.error("No client session available for audio session")
            return
        }

        guard let channel = clientSession.channelManager.channels[event.identifier] as? ProjectionDataChannel else {
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

    private func handleAudioSessionEndedEvent(_ event: AudioSessionEndedEvent) async {
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
