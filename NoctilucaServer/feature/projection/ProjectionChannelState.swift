//
//  ProjectionChannelState.swift
//  NoctilucaServer
//
//  Created by Codex on 2/12/26.
//

import Foundation
@preconcurrency import Combine
import CoreGraphics

import SiriusKit

actor ProjectionChannelState {
    enum SessionKind {
        case video
        case audio
    }

    enum LifecycleState {
        case active
        case destroying
        case destroyed
    }

    struct AppStreamSessionInfo {
        let streamId: UUID
        let bundleId: String
        let pid: pid_t
        let flags: AppStreamFlags
        let windowSubscriptionId: UUID
        let appTerminationSubscriptionId: UUID
        /// AppStream 전용 가상 디스플레이 핸들. `nil`이면 fallback(메인 디스플레이)으로 운영된다.
        let virtualDisplayHandle: NOCVirtualDisplayHandle?
    }

    struct AccessibilitySubscriptionInfo {
        let subscriptionId: UUID
        let pid: pid_t
        let rootNodeId: UUID?
        let eventMask: AccessibilityUpdateType
        let maxDepth: UInt32
        /// `DesktopContextManager.subscribeMenuEvents`가 반환한 메뉴 핸들러 UUID.
        /// Unsubscribe 시 반드시 해제해야 한다.
        let menuEventHandlerId: UUID
        /// `DesktopContextManager.subscribeContextMenuEvents`가 반환한 popup 메뉴 핸들러 UUID.
        /// Unsubscribe 시 menuEventHandlerId 와 함께 해제해야 한다.
        let contextMenuEventHandlerId: UUID
    }

    struct DestroySnapshot {
        let videoSessions: [ProjectionSession]
        let audioSessions: [AudioProjectionSession]
        let dataChannels: [ProjectionDataChannel]
        let cursorSubscription: CursorEventSubscription?
        let displaySubscription: DisplayEventSubscription?
        let appEventSubscriptionId: UUID?
        let appStreamSession: AppStreamSessionInfo?
        let accessibilitySubscriptions: [AccessibilitySubscriptionInfo]
        /// AppStream/싱글윈도우 resize 등 채널이 직접 관리하는 구독을 제외한, 일반
        /// winman `SubscribeWindowEventsRequest` 로 만들어진 구독 UUID 들. destroy 시
        /// 일괄 unsubscribe 한다.
        let windowSubscriptionIds: Set<UUID>
        let virtualDisplayHandles: [NOCVirtualDisplayHandle]
    }

    struct TerminationTargets {
        let videoSession: ProjectionSession?
        let audioSession: AudioProjectionSession?
        let dataChannel: ProjectionDataChannel?
    }

    enum DisplaySubscriptionInstallResult {
        case installed(previous: DisplayEventSubscription?)
        case rejected
    }

    enum DisplayUnsubscribeResult {
        case notFound
        case mismatchedSubscriptionID
        case unsubscribed(DisplayEventSubscription)
    }

    private(set) var lifecycleState: LifecycleState = .active

    private var sessions: [UUID: ProjectionSession] = [:]
    private var audioSessions: [UUID: AudioProjectionSession] = [:]
    private var projectionDataChannels: [UUID: ProjectionDataChannel] = [:]
    private var reservations: [UUID: SessionKind] = [:]
    private var sessionDisplayIDs: [UUID: CGDirectDisplayID] = [:]

    private var cursorSubscription: CursorEventSubscription?
    private var displaySubscription: DisplayEventSubscription?

    private var appEventSubscriptionId: UUID?
    private var appStreamSession: AppStreamSessionInfo?
    private var accessibilitySubscriptions: [UUID: AccessibilitySubscriptionInfo] = [:]
    /// 일반 winman `SubscribeWindowEventsRequest` 로 만들어진 구독 UUID 들. 채널이 닫힐 때
    /// 일괄 unsubscribe 한다. AppStream / singleWindow resize 등 채널이 별도 경로로
    /// 추적하는 구독은 여기에 포함하지 않는다.
    private var windowSubscriptionIds: Set<UUID> = []

    /// 클라이언트가 보낸 wire UUID → 서버 VD handle 매핑.
    /// VirtualDisplayCreate 시 등록, VirtualDisplayDestroy 또는 채널 destroy 시 회수한다.
    private var virtualDisplayHandles: [UUID: NOCVirtualDisplayHandle] = [:]

    /// `DisplayLayoutManager.displayChangeSubject` 구독. 채널 수명과 동일.
    private var displayChangesCancellable: AnyCancellable?

    func reserveSession(identifier: UUID, kind: SessionKind) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard !isIdentifierInUse(identifier) else {
            return false
        }

        reservations[identifier] = kind
        return true
    }

    func registerPendingDataChannel(identifier: UUID, channel: ProjectionDataChannel) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] != nil else {
            return false
        }

        projectionDataChannels[identifier] = channel
        return true
    }

    func activateVideoSession(identifier: UUID, session: ProjectionSession, displayID: CGDirectDisplayID? = nil) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] == .video else {
            return false
        }

        sessions[identifier] = session
        reservations.removeValue(forKey: identifier)

        if let displayID {
            sessionDisplayIDs[identifier] = displayID
        }

        return true
    }

    func activateAudioSession(identifier: UUID, session: AudioProjectionSession) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] == .audio else {
            return false
        }

        audioSessions[identifier] = session
        reservations.removeValue(forKey: identifier)

        return true
    }

    func terminateByControlMessage(identifier: UUID, kind: SessionKind) -> TerminationTargets {
        switch kind {
        case .video:
            let videoSession = sessions.removeValue(forKey: identifier)
            sessionDisplayIDs.removeValue(forKey: identifier)

            if reservations[identifier] == .video {
                reservations.removeValue(forKey: identifier)
            }

            let dataChannel = takeDataChannelIfUnused(identifier: identifier)
            return TerminationTargets(videoSession: videoSession, audioSession: nil, dataChannel: dataChannel)

        case .audio:
            let audioSession = audioSessions.removeValue(forKey: identifier)

            if reservations[identifier] == .audio {
                reservations.removeValue(forKey: identifier)
            }

            let dataChannel = takeDataChannelIfUnused(identifier: identifier)
            return TerminationTargets(videoSession: nil, audioSession: audioSession, dataChannel: dataChannel)
        }
    }

    func terminateByDataChannelClosure(identifier: UUID) -> TerminationTargets {
        let dataChannel = projectionDataChannels.removeValue(forKey: identifier)
        let videoSession = sessions.removeValue(forKey: identifier)
        let audioSession = audioSessions.removeValue(forKey: identifier)

        reservations.removeValue(forKey: identifier)
        sessionDisplayIDs.removeValue(forKey: identifier)

        return TerminationTargets(videoSession: videoSession, audioSession: audioSession, dataChannel: dataChannel)
    }

    func sessionForPerformanceReport(identifier: UUID) -> ProjectionSession? {
        sessions[identifier]
    }

    func videoSessionIdentifiers(forDisplayID displayID: CGDirectDisplayID) -> [UUID] {
        sessionDisplayIDs.filter { $0.value == displayID }.map { $0.key }
    }

    func addCursorSubscriptionIfAbsent(_ subscription: CursorEventSubscription) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard cursorSubscription == nil else {
            return false
        }

        cursorSubscription = subscription
        return true
    }

    func isCurrentCursorSubscription(_ subscription: CursorEventSubscription) -> Bool {
        cursorSubscription === subscription
    }

    func removeCursorSubscription() -> CursorEventSubscription? {
        let subscription = cursorSubscription
        cursorSubscription = nil
        return subscription
    }

    func replaceDisplaySubscription(_ subscription: DisplayEventSubscription) -> DisplaySubscriptionInstallResult {
        guard lifecycleState == .active else {
            return .rejected
        }

        let previous = displaySubscription
        displaySubscription = subscription

        return .installed(previous: previous)
    }

    func isCurrentDisplaySubscription(_ subscription: DisplayEventSubscription) -> Bool {
        displaySubscription === subscription
    }

    func unsubscribeDisplaySubscription(expectedID: UUID) -> DisplayUnsubscribeResult {
        guard let subscription = displaySubscription else {
            return .notFound
        }

        guard subscription.id == expectedID else {
            return .mismatchedSubscriptionID
        }

        displaySubscription = nil
        return .unsubscribed(subscription)
    }

    // MARK: - App Event Subscription

    func setAppEventSubscription(id: UUID) -> Bool {
        guard lifecycleState == .active else { return false }
        appEventSubscriptionId = id
        return true
    }

    func removeAppEventSubscription() -> UUID? {
        let id = appEventSubscriptionId
        appEventSubscriptionId = nil
        return id
    }

    // MARK: - AppStream Session

    func activateAppStreamSession(_ session: AppStreamSessionInfo) -> Bool {
        guard lifecycleState == .active else { return false }
        guard appStreamSession == nil else { return false }
        appStreamSession = session
        return true
    }

    func currentAppStreamSession() -> AppStreamSessionInfo? {
        appStreamSession
    }

    func removeAppStreamSession(streamId: UUID) -> AppStreamSessionInfo? {
        guard appStreamSession?.streamId == streamId else { return nil }
        let session = appStreamSession
        appStreamSession = nil
        return session
    }

    func removeAppStreamSessionForTerminatedApp(bundleId: String) -> AppStreamSessionInfo? {
        guard appStreamSession?.bundleId == bundleId else { return nil }
        let session = appStreamSession
        appStreamSession = nil
        return session
    }

    // MARK: - Accessibility Subscriptions

    func addAccessibilitySubscription(_ info: AccessibilitySubscriptionInfo) -> Bool {
        guard lifecycleState == .active else { return false }
        accessibilitySubscriptions[info.subscriptionId] = info
        return true
    }

    func removeAccessibilitySubscription(id: UUID) -> AccessibilitySubscriptionInfo? {
        return accessibilitySubscriptions.removeValue(forKey: id)
    }

    func allAccessibilitySubscriptions() -> [AccessibilitySubscriptionInfo] {
        return Array(accessibilitySubscriptions.values)
    }

    func accessibilitySubscriptions(forPid pid: pid_t) -> [AccessibilitySubscriptionInfo] {
        return accessibilitySubscriptions.values.filter { $0.pid == pid }
    }

    // MARK: - Window Subscription Tracking

    /// 일반 winman 구독 UUID 를 등록한다. lifecycle 이 active 일 때만 받아들이며 그 외에는
    /// 호출자가 즉시 unsubscribe 해야 한다.
    @discardableResult
    func addWindowSubscription(id: UUID) -> Bool {
        guard lifecycleState == .active else { return false }
        windowSubscriptionIds.insert(id)
        return true
    }

    @discardableResult
    func removeWindowSubscription(id: UUID) -> Bool {
        return windowSubscriptionIds.remove(id) != nil
    }

    // MARK: - Destroy

    func beginDestroy() -> DestroySnapshot? {
        guard lifecycleState == .active else {
            return nil
        }

        lifecycleState = .destroying

        // AppStream session 이 활성이면 그 windowSubscriptionId 는 cleanupAppStreamSession 이
        // 별도로 정리하므로 일반 winman set 에서 제외해 중복 unsubscribe 를 막는다.
        var winmanSubscriptionIds = windowSubscriptionIds
        if let appStream = appStreamSession {
            winmanSubscriptionIds.remove(appStream.windowSubscriptionId)
        }

        let snapshot = DestroySnapshot(
            videoSessions: Array(sessions.values),
            audioSessions: Array(audioSessions.values),
            dataChannels: Array(projectionDataChannels.values),
            cursorSubscription: cursorSubscription,
            displaySubscription: displaySubscription,
            appEventSubscriptionId: appEventSubscriptionId,
            appStreamSession: appStreamSession,
            accessibilitySubscriptions: Array(accessibilitySubscriptions.values),
            windowSubscriptionIds: winmanSubscriptionIds,
            virtualDisplayHandles: Array(virtualDisplayHandles.values)
        )

        sessions.removeAll()
        audioSessions.removeAll()
        projectionDataChannels.removeAll()
        reservations.removeAll()
        sessionDisplayIDs.removeAll()
        virtualDisplayHandles.removeAll()
        accessibilitySubscriptions.removeAll()
        windowSubscriptionIds.removeAll()

        cursorSubscription = nil
        displaySubscription = nil
        appEventSubscriptionId = nil
        appStreamSession = nil

        return snapshot
    }

    func completeDestroy() {
        lifecycleState = .destroyed

        displayChangesCancellable?.cancel()
        displayChangesCancellable = nil
    }

    /// `DisplayLayoutManager` 의 disconnect 이벤트를 구독해 `callback` 으로 라우팅합니다.
    /// 이 메서드는 채널 수명 동안 **정확히 한 번** 호출되어야 합니다 (ProjectionChannel.init 에서).
    /// Combine sink 는 `AnyCancellable` 로 actor 내부에 보관하여 Sendable 을 만족시킵니다.
    func installDisplayDisconnectSink(
        _ callback: @escaping @Sendable (CGDirectDisplayID) -> Void
    ) async {
        self.displayChangesCancellable = await (Task { @MainActor in
            DisplayLayoutManager.shared.displayChangeSubject
                .filter { $0.eventType.contains(.disconnected) }
                .sink { event in
                    callback(event.displayID)
                }
        }).value
    }

    // MARK: - Virtual Display Registry

    /// 주어진 wire UUID 목록 중 이미 등록되어 있거나 목록 내부에서 중복되는 첫 번째 UUID를 반환한다.
    func virtualDisplayIdentifierConflict(in candidates: [UUID]) -> UUID? {
        var seen: Set<UUID> = []
        for id in candidates {
            if virtualDisplayHandles[id] != nil { return id }
            if !seen.insert(id).inserted { return id }
        }
        return nil
    }

    /// 채널 lifecycle이 active이고 externalID가 비어 있을 때만 등록한다.
    func registerVirtualDisplay(externalID: UUID, handle: NOCVirtualDisplayHandle) -> Bool {
        guard lifecycleState == .active else { return false }
        guard virtualDisplayHandles[externalID] == nil else { return false }

        virtualDisplayHandles[externalID] = handle
        return true
    }

    /// externalID로 등록된 핸들을 꺼내고 레지스트리에서 제거한다.
    func takeVirtualDisplay(externalID: UUID) -> NOCVirtualDisplayHandle? {
        return virtualDisplayHandles.removeValue(forKey: externalID)
    }

    /// rollback 경로용. handle을 직접 받아서 일치하는 entry를 제거한다.
    func unregisterVirtualDisplay(_ handle: NOCVirtualDisplayHandle) {
        for (externalID, registered) in virtualDisplayHandles where registered === handle {
            virtualDisplayHandles.removeValue(forKey: externalID)
            return
        }
    }

    /// 주어진 CGDirectDisplayID에 대응하는 wire UUID를 반환한다. (DisplayInfo.virtualDisplayIdentifier 채우기용)
    func virtualDisplayExternalID(forDisplayID displayID: CGDirectDisplayID) -> UUID? {
        for (externalID, handle) in virtualDisplayHandles where handle.displayID == displayID {
            return externalID
        }
        return nil
    }

    /// 채널에 등록된 가상 디스플레이 중 `purpose` 와 일치하는 핸들들을 반환한다.
    /// AppStream 시작 시 클라가 사전에 만들어둔 VD pool 을 조회할 때 사용한다.
    func virtualDisplays(withPurpose purpose: NOCVirtualDisplayPurpose) -> [NOCVirtualDisplayHandle] {
        return virtualDisplayHandles.values.filter { $0.purpose == purpose }
    }

    /// `purpose` 와 일치하는 모든 가상 디스플레이를 레지스트리에서 회수해 반환한다.
    /// AppStream 종료 시 일괄 destroy 안전망에서 사용한다.
    func takeVirtualDisplays(withPurpose purpose: NOCVirtualDisplayPurpose) -> [NOCVirtualDisplayHandle] {
        let matching = virtualDisplayHandles.filter { $0.value.purpose == purpose }
        for key in matching.keys {
            virtualDisplayHandles.removeValue(forKey: key)
        }
        return Array(matching.values)
    }

    private func isIdentifierInUse(_ identifier: UUID) -> Bool {
        sessions[identifier] != nil ||
        audioSessions[identifier] != nil ||
        reservations[identifier] != nil ||
        projectionDataChannels[identifier] != nil
    }

    private func takeDataChannelIfUnused(identifier: UUID) -> ProjectionDataChannel? {
        let hasLiveSession = sessions[identifier] != nil || audioSessions[identifier] != nil
        let hasReservation = reservations[identifier] != nil

        guard !hasLiveSession && !hasReservation else {
            return nil
        }

        return projectionDataChannels.removeValue(forKey: identifier)
    }
}
