//
//  RemoteSession+Projection.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/1/26.
//

import Foundation
import Atomics

import Combine

import CoreGraphics

import SiriusKitClient

// MARK: - Retryable reason extensions

extension AudioSessionEndReason {
    var isRetryable: Bool {
        switch self {
        case .error, .unknown:
            return true
        case .clientRequested, .sourceUnavailable:
            return false
        default:
            return true
        }
    }
}

extension RemoteSession {
    typealias CursorHash = UInt64
    
    struct CursorImage: Identifiable {
        let id: CursorHash
        let image: CGImage
        let size: CGSize
        let hotspot: CGPoint
    }
    
    /// 커서 이미지를 캐싱합니다.
    ///
    /// `ConcurrentDictionary` 기반이라 thread-safe. `Projection` 클래스는
    /// `@MainActor` 격리되지만, 이 캐시는 백그라운드 PNG 디코딩 task 에서도
    /// 읽혀야 하므로 `nonisolated let` 필드로 노출한다.
    fileprivate final class CursorImageCacheManager: @unchecked Sendable {
        let cache = ConcurrentDictionary<CursorHash, CursorImage>()

        func updateCache(_ image: CursorImage) {
            self.cache[image.id] = image
        }
    }
    
    class CursorState: ObservableObject {
        @Published
        var image: CursorImage? = nil
        
        @Published
        var displayID: Int? = nil
        
        @Published
        var position: CGPoint = .zero
    }
    
    /// 프로젝션 세션 종료 정보 (auto-restart 실패 시 UI에 전달)
    struct ProjectionSessionFailureInfo {
        let reason: VideoSessionEndReason
        let message: String?
    }

    /// 오디오 세션 종료 정보
    struct AudioSessionFailureInfo {
        let reason: AudioSessionEndReason
        let message: String?
    }

    /// auto-restart를 위한 재시도 상태
    private struct RetryState {
        var attemptCount: Int = 0
        let maxRetries: Int = 3
        var isRetrying: Bool = false

        mutating func reset() {
            attemptCount = 0
            isRetrying = false
        }

        mutating func nextBackoff() -> TimeInterval? {
            guard attemptCount < maxRetries else { return nil }
            let backoff = pow(2.0, Double(attemptCount)) // 1s, 2s, 4s
            attemptCount += 1
            return backoff
        }
    }

    /// 이 티켓은 다른 곳으로 복사할 수 없습니다
    class SessionReferenceTicket {
        let id: UUID
        let releaseAction: () -> Void
        private(set) var isReleased = false

        fileprivate init(id: UUID, releaseAction: @escaping () -> Void) {
            self.id = id
            self.releaseAction = releaseAction
        }

        /// 명시적 해제. 중복 호출 안전.
        func release() {
            guard !isReleased else { return }
            isReleased = true
            releaseAction()
        }

        deinit {
            if !isReleased {
                releaseAction()
            }
        }
    }
    
    @MainActor
    final class Projection: ObservableObject {
        private let logger = NoctilucaLogger(category: "RemoteSession.Projection")

        private weak var parent: RemoteSession?
        private(set) var channel: ProjectionChannel

        let channelID: UUID

        private var eventConsumerTask: Task<Void, Never>? = nil

        @Published
        private(set) var projectionSessions: [UUID: ProjectionSession] = [:]
        private(set) var projectionSessionReferences: [UUID: ManagedAtomic<Int>] = [:]

        @Published
        private(set) var audioSessions: [UUID: AudioProjectionSession] = [:]

        /// 현재 활성화된 DegradationNotice. nil이면 notice를 받지 않았거나 회복된 상태.
        @Published
        private(set) var degradationNotice: DegradationNotice? = nil

        /// 프로젝션 세션 오류 정보. auto-restart 실패 시 설정됨.
        @Published
        private(set) var sessionError: ProjectionSessionFailureInfo? = nil

        /// 오디오 세션 오류 정보.
        @Published
        private(set) var audioSessionError: AudioSessionFailureInfo? = nil

        private var audioRetryState = RetryState()
        private var audioRetryTask: Task<Void, Never>?

        private var sessionEventTasks: [UUID: Task<Void, Never>] = [:]

        nonisolated private let cursorImageCacheManager = CursorImageCacheManager()
        let cursorState = CursorState()
        private var pendingCursorMoveEvent: CursorMoveEvent?
        private var isCursorMoveDeliveryScheduled = false
        
        init(_ parent: RemoteSession, channel: ProjectionChannel) {
            self.parent = parent
            self.channel = channel

            // cache the channel ID
            self.channelID = channel.identifier

            subscribeEvents()
        }

        deinit {
            // nonisolated context. MainActor-isolated 메서드 직접 호출 불가 —
            // Task<Void, Never> 과 AnyCancellable 의 cancel() 은 Sendable 이므로 OK.
            audioRetryTask?.cancel()
            eventConsumerTask?.cancel()
            for task in sessionEventTasks.values {
                task.cancel()
            }
        }

        private func subscribeEvents() {
            self.eventConsumerTask = Task { [weak self] in
                guard let channel = self?.channel else { return }
                for await event in channel.events {
                    guard let self else { return }
                    self.handleEvent(event)
                }
            }
        }


        private func unsubscribeEvents() {
            self.eventConsumerTask?.cancel()
            self.eventConsumerTask = nil
        }
        
        private func handleEvent(_ event: ProjectionChannelEvent) {
            switch event {
            case .sessionCreated(let session):
                self.projectionSessions.updateValue(session, forKey: session.dataChannel.identifier)
                self.subscribeSessionEvents(session)
                self.sessionError = nil
            case .sessionDestroyed(let sessionID, let reason, let message):
                self.projectionSessions.removeValue(forKey: sessionID)
                self.projectionSessionReferences.removeValue(forKey: sessionID)
                self.unsubscribeSessionEvents(sessionID)
                if projectionSessions.isEmpty {
                    self.degradationNotice = nil
                }
                self.notifySessionFailure(reason: reason, message: message)

            case .audioSessionCreated(let audioSession):
                let dataChannelID = audioSession.dataChannel.identifier
                self.audioSessions.updateValue(audioSession, forKey: dataChannelID)
                self.audioRetryState.reset()
                self.audioSessionError = nil
            case .audioSessionDestroyed(let sessionID, let reason, let message):
                self.audioSessions.removeValue(forKey: sessionID)
                if reason.isRetryable {
                    self.attemptAudioAutoRestart(reason: reason, message: message)
                }

            case .cursorMoved(let moveEvent):
                self.enqueueCursorMoveEvent(moveEvent)
            case .cursorImageChanged(let imageEvent):
                Task.detached { [weak self] in
                    guard let self else { return }

                    // 캐시 확인 (MainActor 불필요 — cache 읽기는 non-isolated)
                    if let cachedImage = self.cursorImageCacheManager.cache[imageEvent.cursorType] {
                        await MainActor.run {
                            self.cursorState.image = cachedImage
                        }
                        return
                    }

                    // PNG 디코딩을 백그라운드에서 수행
                    guard let imageData = imageEvent.imageData,
                          let dataProvider = CGDataProvider(data: imageData as CFData),
                          let image = CGImage(
                              pngDataProviderSource: dataProvider,
                              decode: nil,
                              shouldInterpolate: true,
                              intent: .defaultIntent
                          ) else {
                        return
                    }

                    let cursorImage = CursorImage(
                        id: imageEvent.cursorType,
                        image: image,
                        size: imageEvent.size.cgSize,
                        hotspot: imageEvent.hotspot.cgPoint
                    )

                    // UI 업데이트만 MainActor에서 수행
                    await MainActor.run {
                        self.cursorImageCacheManager.updateCache(cursorImage)
                        self.cursorState.image = cursorImage
                    }
                }

            case .appStreamWindowEvent(let appStreamEvent):
#if os(macOS)
                guard let appStreamWindowManager = parent?.appStreamWindowManager else {
                    return
                }
                
                appStreamWindowManager.handleAppStreamWindowEvent(appStreamEvent)
#endif
                break
            }
        }

        private func subscribeSessionEvents(_ session: ProjectionSession) {
            let sessionID = session.dataChannel.identifier

            let task = Task { [weak self] in
                for await event in session.events {
                    guard let self else { return }
                    self.handleSessionEvent(event)
                }
            }

            sessionEventTasks[sessionID] = task
        }

        private func unsubscribeSessionEvents(_ sessionID: UUID) {
            sessionEventTasks[sessionID]?.cancel()
            sessionEventTasks.removeValue(forKey: sessionID)
        }

        private func handleSessionEvent(_ event: ProjectionSessionEvent) {
            switch event {
            case .degradationNoticeReceived(let notice):
                if notice.reason.rawValue == 0 && notice.type.rawValue == 0 && notice.additionalInfo.rawValue == 0 {
                    self.degradationNotice = nil
                } else {
                    self.degradationNotice = notice
                }
            case .errorOccurred(let error, let fatal):
                if fatal {
                    logger.error("Fatal projection session error: \(error.localizedDescription)")
                } else {
                    logger.warning("Non-fatal projection session error: \(error.localizedDescription)")
                }
            default:
                break
            }
        }

        private func enqueueCursorMoveEvent(_ moveEvent: CursorMoveEvent) {
            // @MainActor 격리이므로 lock 없이도 race 없음.
            pendingCursorMoveEvent = moveEvent

            guard !isCursorMoveDeliveryScheduled else {
                return
            }
            isCursorMoveDeliveryScheduled = true

            // coalesce: 같은 turn 내의 다중 move 를 하나로 합친다.
            Task { @MainActor [weak self] in
                self?.drainCoalescedCursorMoveEvent()
            }
        }

        private func drainCoalescedCursorMoveEvent() {
            let moveEvent = pendingCursorMoveEvent
            pendingCursorMoveEvent = nil
            isCursorMoveDeliveryScheduled = false

            guard let moveEvent else {
                return
            }

            handleCursorMoveEvent(moveEvent)
        }
        
        private func handleCursorMoveEvent(_ moveEvent: CursorMoveEvent) {
            self.cursorState.displayID = Int(moveEvent.displayID)
            self.cursorState.position = moveEvent.position.cgPoint
        }
        
        @MainActor
        private func handleCursorImageEvent(_ imageEvent: CursorImageEvent) {
            let cursorHash = imageEvent.cursorType
            
            if let cursorImage = self.cursorImageCacheManager.cache[cursorHash] {
                // use cached image
                self.cursorState.image = cursorImage
                return
            }
            
            if let imageData = imageEvent.imageData,
               let dataProvider = CGDataProvider(data: imageData as CFData) {
                
                guard let image = CGImage(
                    pngDataProviderSource: dataProvider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                ) else {
                    return
                }
                
                let cursorImage = CursorImage(
                    id: imageEvent.cursorType,
                    image: image,
                    size: imageEvent.size.cgSize,
                    hotspot: imageEvent.hotspot.cgPoint
                )
                
                // update cache
                self.cursorImageCacheManager.updateCache(cursorImage)
                
                // update state
                self.cursorState.image = cursorImage
            }
        }
        
        /// 프로젝션 세션을 '구독'합니다.
        ///
        /// # ABOUT 'REFERENCE TICKET'
        ///
        /// - 이 function을 호출하면, '레퍼런스 티켓'을 발급받습니다.
        /// - 레퍼런스 티켓은 '프로젝션 세션'으로의 레퍼런스입니다.
        /// - 각 프로젝션 세션은 자신을 레퍼런싱하는 '레퍼런스 티켓'이 사라지면 자동으로 종료됩니다.
        ///
        // TODO: 디스플레이마다 해상도 다른데 어떻게 할려고?
        // 디스플레이가 2대 이상이면 하드웨어 인코더가 터질텐데 어떻게 할려고???
        @MainActor
        func subscribeProjectionSession(for source: ProjectionSourceDescriptor) async throws -> ProjectionSessionSubscription {
            if let sessionKey = projectionSessions.first(where: { $0.value.sourceDescriptor == source })?.key {
                // 이미 해당 소스에 대한 프로젝션 세션이 존재함
                logger.info("Projection session for \(source.debugDescription) already exists.")
                guard let referenceCounter = projectionSessionReferences[sessionKey] else {
                    // ASSERTION: 레퍼런스 카운터는 반드시 존재해야만 한다
                    fatalError("ASSERTION FAILED: reference counter for existing projection session is missing.")
                }

                guard let session = projectionSessions[sessionKey] else {
                    fatalError("ASSERTION FAILED: projection session for key \(sessionKey) is missing.")
                }

                // += 1
                referenceCounter.wrappingIncrement(ordering: .relaxed)

                let ticket = SessionReferenceTicket(id: UUID()) {
                    referenceCounter.wrappingDecrement(ordering: .releasing)

                    Task {
                        await self.handleSessionReferenceDecrement(for: sessionKey)
                    }
                }

                return ProjectionSessionSubscription(session: session, ticket: ticket, rendererImplementation: SettingsStore.shared.settings.projection.rendererImplementation)
            }

            guard let session = try await parent?.client.projectionChannel.createSession(
                for: source,
                projectionSettings: parent?.client.sessionSettings?.projection
            ) else {
                throw ProjectionChannelError.channelClosed
            }

            let sessionID = session.id

            // 레퍼런스 카운터 초기화
            let referenceCounter = ManagedAtomic<Int>(1)
            projectionSessionReferences[sessionID] = referenceCounter

            let ticket = SessionReferenceTicket(id: UUID()) {
                referenceCounter.wrappingDecrement(ordering: .releasing)

                Task {
                    await self.handleSessionReferenceDecrement(for: sessionID)
                }
            }

            return ProjectionSessionSubscription(session: session, ticket: ticket, rendererImplementation: SettingsStore.shared.settings.projection.rendererImplementation)
        }

        // MARK: - Auto-restart (Audio)

        private func attemptAudioAutoRestart(reason: AudioSessionEndReason, message: String?) {
            guard !audioRetryState.isRetrying else { return }

            guard let backoff = audioRetryState.nextBackoff() else {
                self.audioSessionError = AudioSessionFailureInfo(reason: reason, message: message)
                return
            }

            audioRetryState.isRetrying = true
            logger.info("Auto-restarting audio session after \(backoff)s (attempt \(self.audioRetryState.attemptCount)/\(self.audioRetryState.maxRetries))")

            audioRetryTask = Task { [weak self] in
                guard let self else { return }

                try? await Task.sleep(for: .seconds(backoff))
                guard !Task.isCancelled else { return }

                do {
                    try await self.startAudioProjection()
                    self.audioRetryState.reset()
                    self.audioSessionError = nil
                    logger.info("Audio auto-restart succeeded")
                } catch {
                    self.audioRetryState.isRetrying = false
                    logger.error("Audio auto-restart failed: \(error)")
                    if self.audioRetryState.attemptCount >= self.audioRetryState.maxRetries {
                        self.audioSessionError = AudioSessionFailureInfo(
                            reason: reason,
                            message: "Audio auto-restart failed after \(self.audioRetryState.maxRetries) attempts: \(error.localizedDescription)"
                        )
                    } else {
                        self.attemptAudioAutoRestart(reason: reason, message: message)
                    }
                }
            }
        }

        private func notifySessionFailure(reason: VideoSessionEndReason, message: String?) {
            self.sessionError = ProjectionSessionFailureInfo(reason: reason, message: message)
            logger.error("Projection session failure: reason=\(reason.rawValue), message=\(message ?? "(nil)")")
        }

        /// auto-restart 재시도 상태를 초기화하고 진행 중인 재시도를 취소합니다.
        func cancelAutoRestart() {
            audioRetryTask?.cancel()
            audioRetryTask = nil
            audioRetryState.reset()
        }

        func startAudioProjection() async throws {
            guard await parent?.client.sessionSettings?.projection.isAudioProjectionEnabled ?? false else {
                logger.info("Audio projection is disabled by settings, skipping.")
                return
            }

            // TODO: 마이크 세션같은게 있을 수도 있기 때문에
            guard audioSessions.values.isEmpty else {
                // 이미 오디오 프로젝션 세션이 존재함
                logger.info("Audio projection session already exists.")
                return
            }
            
            _ = try await parent?.client.projectionChannel.createAudioSession(for: .sessionAudio, projectionSettings: parent?.client.sessionSettings?.projection)
        }
        
    }
}

fileprivate extension RemoteSession.Projection {
    @MainActor
    func handleSessionReferenceDecrement(for sessionID: UUID) async {
        guard let referenceCounter = projectionSessionReferences[sessionID] else {
            return
        }
        
        let count = referenceCounter.load(ordering: .acquiring)
        
        if count == 0 {
            // 레퍼런스 카운터가 0이 되었으므로 세션 종료
            logger.info("Reference count for projection session \(sessionID) reached zero. Stopping session.")
            
            if let session = projectionSessions.removeValue(forKey: sessionID) {
                do {
                    try await session.stop()
                } catch {
                    logger.error("Failed to stop projection session \(sessionID): \(error)")
                }
            }
            
            // 레퍼런스 카운터 제거
            projectionSessionReferences.removeValue(forKey: sessionID)
        }
    }
}
