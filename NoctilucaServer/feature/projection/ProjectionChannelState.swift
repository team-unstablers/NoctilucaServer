//
//  ProjectionChannelState.swift
//  NoctilucaServer
//
//  Created by Codex on 2/12/26.
//

import Foundation

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

    struct DestroySnapshot {
        let videoSessions: [ProjectionSession]
        let audioSessions: [AudioProjectionSession]
        let dataChannels: [ProjectionDataChannel]
        let cursorSubscription: CursorEventSubscription?
        let displaySubscription: DisplayEventSubscription?
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

    private var cursorSubscription: CursorEventSubscription?
    private var displaySubscription: DisplayEventSubscription?

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

    func activateVideoSession(identifier: UUID, session: ProjectionSession) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] == .video else {
            return false
        }

        sessions[identifier] = session
        reservations.removeValue(forKey: identifier)

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

        return TerminationTargets(videoSession: videoSession, audioSession: audioSession, dataChannel: dataChannel)
    }

    func sessionForPerformanceReport(identifier: UUID) -> ProjectionSession? {
        sessions[identifier]
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

    func beginDestroy() -> DestroySnapshot? {
        guard lifecycleState == .active else {
            return nil
        }

        lifecycleState = .destroying

        let snapshot = DestroySnapshot(
            videoSessions: Array(sessions.values),
            audioSessions: Array(audioSessions.values),
            dataChannels: Array(projectionDataChannels.values),
            cursorSubscription: cursorSubscription,
            displaySubscription: displaySubscription
        )

        sessions.removeAll()
        audioSessions.removeAll()
        projectionDataChannels.removeAll()
        reservations.removeAll()

        cursorSubscription = nil
        displaySubscription = nil

        return snapshot
    }

    func completeDestroy() {
        lifecycleState = .destroyed
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
