//
//  RemoteSession+Projection.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/1/26.
//

import Foundation
import Atomics

import Observation

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

extension VideoSessionEndReason {
    var isRetryable: Bool {
        switch self {
        case .clientRequested:
            return false
        default:
            return true
        }
    }
}

/// 비디오 세션 자동 재시도 시 발생할 수 있는 오류.
enum ProjectionRetryError: Error {
    /// 재시도 시점에 디스플레이가 사라져서 더 이상 시도할 의미가 없음.
    case displayDisappeared
    /// 모든 backoff 시도가 실패함.
    case exhausted
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
    
    @MainActor
    @Observable
    final class CursorState {
        var image: CursorImage? = nil

        var displayID: Int? = nil

        var position: CGPoint = .zero
    }
    
    /// 프로젝션 세션 종료 정보 (auto-restart 실패 시 UI에 전달)
    struct ProjectionSessionFailureInfo: Equatable {
        let reason: VideoSessionEndReason
        let message: String?
    }

    /// 오디오 세션 종료 정보
    struct AudioSessionFailureInfo: Equatable {
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
    @Observable
    final class Projection {
        private let logger = NoctilucaLogger(category: "RemoteSession.Projection")

        private weak var parent: RemoteSession?
        private(set) var channel: ProjectionChannel

        let channelID: UUID

        @ObservationIgnored
        private var eventConsumerTask: Task<Void, Never>? = nil

        private(set) var projectionSessions: [UUID: ProjectionSession] = [:]
        @ObservationIgnored
        private(set) var projectionSessionReferences: [UUID: ManagedAtomic<Int>] = [:]

        /// 진행 중인 `subscribeProjectionSession(for:)` 호출의 in-flight `createSession` Task.
        ///
        /// 같은 displayID 에 대해 두 번째 호출이 들어왔을 때, 이미 진행 중인 createSession 이
        /// 있으면 그 결과를 await 하여 같은 `ProjectionSession` 을 공유한다. 이 dict 가 없으면
        /// `await createSession(...)` 에서 MainActor reentrancy 로 동시 두 호출이 모두 createSession
        /// 을 부르면서 같은 displayID 에 대해 세션이 두 개 만들어지는 race 가 발생한다.
        @ObservationIgnored
        private var pendingSubscribeTasks: [Int: Task<ProjectionSession, Error>] = [:]

        private(set) var audioSessions: [UUID: AudioProjectionSession] = [:]

        /// 현재 활성화된 DegradationNotice. nil이면 notice를 받지 않았거나 회복된 상태.
        private(set) var degradationNotice: DegradationNotice? = nil

        /// 디스플레이 단위 프로젝션 세션 오류 정보.
        ///
        /// 멀티 디스플레이 환경에서 각 디스플레이의 세션이 독립적으로 종료될 수 있으므로
        /// `displayID` 를 키로 하는 dict 로 관리한다. View 측은 자신이 보고 있는
        /// `displayID` 의 항목을 `onChange` 로 관찰하여 fallback / 재시도 정책을 결정한다.
        private(set) var sessionErrors: [Int: ProjectionSessionFailureInfo] = [:]

        /// 오디오 세션 오류 정보.
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

        @MainActor
        deinit {
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
                // 새 세션이 만들어졌다는 것은 해당 디스플레이가 다시 정상화되었다는 의미이므로 에러 클리어
                self.sessionErrors.removeValue(forKey: session.displayID)
            case .sessionDestroyed(let sessionID, let displayID, let reason, let message):
                self.projectionSessions.removeValue(forKey: sessionID)
                self.projectionSessionReferences.removeValue(forKey: sessionID)
                self.unsubscribeSessionEvents(sessionID)
                if projectionSessions.isEmpty {
                    self.degradationNotice = nil
                }
                self.notifySessionFailure(displayID: displayID, reason: reason, message: message)

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
        func subscribeProjectionSession(for displayID: Int) async throws -> ProjectionSessionSubscription {
            if let session = projectionSessions.first(where: { $0.value.displayID == displayID })?.value {
                // 이미 해당 디스플레이에 대한 프로젝션 세션이 존재함
                logger.info("Projection session for displayID \(displayID) already exists.")
                return makeSubscription(for: session)
            }

            // 같은 displayID 에 대해 createSession 이 이미 진행 중이면, 그 Task 의 결과를 공유한다.
            // (같은 turn 내 호출은 dict 조회가 동기적으로 이루어지므로 race 가 없다.)
            if let inflight = pendingSubscribeTasks[displayID] {
                logger.info("Projection session for displayID \(displayID) is in-flight; awaiting shared task.")
                let session = try await inflight.value
                return makeSubscription(for: session)
            }

            // 새 createSession Task 를 등록한다. Task 안에서 dict 정리까지 책임진다.
            let task = Task<ProjectionSession, Error> { [weak self] in
                guard let self else { throw ProjectionChannelError.channelClosed }

                defer { self.pendingSubscribeTasks.removeValue(forKey: displayID) }

                guard let session = try await self.parent?.client.projectionChannel.createSession(
                    for: displayID,
                    projectionSettings: self.parent?.client.sessionSettings?.projection
                ) else {
                    throw ProjectionChannelError.channelClosed
                }

                // 레퍼런스 카운터 초기화 (subscription 발급은 호출자가 makeSubscription 에서 처리)
                self.projectionSessionReferences[session.id] = ManagedAtomic<Int>(0)
                return session
            }
            pendingSubscribeTasks[displayID] = task

            let session = try await task.value
            return makeSubscription(for: session)
        }

        /// 주어진 `ProjectionSession` 에 대해 reference count 를 1 증가시키고 새 ticket 으로
        /// `ProjectionSessionSubscription` 을 발급한다. 호출자는 항상 MainActor 에 있어야 한다.
        @MainActor
        private func makeSubscription(for session: ProjectionSession) -> ProjectionSessionSubscription {
            let sessionID = session.id
            guard let referenceCounter = projectionSessionReferences[sessionID] else {
                fatalError("ASSERTION FAILED: reference counter for projection session \(sessionID) is missing.")
            }

            referenceCounter.wrappingIncrement(ordering: .relaxed)

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

        private func notifySessionFailure(displayID: Int?, reason: VideoSessionEndReason, message: String?) {
            guard let displayID else {
                // displayID 가 없는 케이스 (예: SingleWindow projection source) 는 현재 미사용.
                // AppStream 도입 시 별도 키 체계가 필요하므로 일단 로그만 남기고 폐기한다.
                logger.warning("Projection session failure with no displayID: reason=\(reason.rawValue), message=\(message ?? "(nil)")")
                return
            }
            self.sessionErrors[displayID] = ProjectionSessionFailureInfo(reason: reason, message: message)
            logger.error("Projection session failure: displayID=\(displayID), reason=\(reason.rawValue), message=\(message ?? "(nil)")")
        }

        /// 사용자 / View 측이 명시적으로 에러 상태를 클리어할 때 호출합니다.
        /// (예: 수동 재시도 트리거, 다른 디스플레이로 전환)
        func clearSessionError(for displayID: Int) {
            sessionErrors.removeValue(forKey: displayID)
        }

        // MARK: - Auto-retry (Video)

        /// 비디오 세션 backoff 재시도 스케줄 (오디오 자동 재시작과 동일).
        private static let videoRetryBackoffSchedule: [TimeInterval] = [1, 2, 4]

        /// 1s / 2s / 4s backoff 로 최대 3회 `subscribeProjectionSession(for:)` 을 재시도합니다.
        ///
        /// - 매 시도 직전에 `displayLayoutManager.displayLayouts[displayID]` 의 존재 여부를
        ///   확인하여 디스플레이가 이미 사라졌으면 `ProjectionRetryError.displayDisappeared` 를
        ///   throw 하고 즉시 종료합니다.
        /// - 한 번이라도 성공하면 `sessionErrors[displayID]` 를 클리어하고 새 subscription 을
        ///   반환합니다.
        /// - 모든 시도가 실패하면 마지막 오류를 throw 합니다.
        ///
        /// 호출자는 `Task` 로 감싸 보유하다가 `currentProjectionTarget` 변경 시 cancel 하여
        /// 진행 중인 retry 를 중단할 수 있습니다.
        @MainActor
        func subscribeWithBackoff(for displayID: Int) async throws -> ProjectionSessionSubscription {
            var lastError: Error?
            let schedule = Self.videoRetryBackoffSchedule
            for (i, backoff) in schedule.enumerated() {
                logger.info("Video session retry: display=\(displayID), attempt=\(i + 1)/\(schedule.count), backoff=\(backoff)s")

                try? await Task.sleep(for: .seconds(backoff))
                try Task.checkCancellation()

                // 시점에 따라 디스플레이가 사라졌을 수 있으므로 매번 재확인
                guard channel.displayLayoutManager.displayLayouts[displayID] != nil else {
                    logger.info("Video session retry aborted: display \(displayID) is no longer available")
                    throw ProjectionRetryError.displayDisappeared
                }

                do {
                    let subscription = try await subscribeProjectionSession(for: displayID)
                    sessionErrors.removeValue(forKey: displayID)
                    logger.info("Video session retry succeeded for display \(displayID) (attempt \(i + 1))")
                    return subscription
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.warning("Video session retry attempt \(i + 1) failed for display \(displayID): \(error.localizedDescription)")
                    lastError = error
                }
            }
            logger.error("Video session retry exhausted for display \(displayID)")
            throw lastError ?? ProjectionRetryError.exhausted
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
