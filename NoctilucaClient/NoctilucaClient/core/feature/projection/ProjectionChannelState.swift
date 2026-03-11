//
//  ProjectionChannelState.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/15/26.
//

import Foundation
import SiriusKitClient

struct PendingAudioSessionRequest: Sendable {
    let continuation: CheckedContinuation<AudioSessionCreatedEvent, Error>
    let timeoutTask: Task<Void, Never>
}

/// ProjectionChannel의 mutable state를 actor isolation으로 보호합니다.
actor ProjectionChannelState {
    var sessions: [UUID: ProjectionSession] = [:]
    var audioSessions: [UUID: AudioProjectionSession] = [:]

    private var pendingSessions: [UUID: @Sendable (any DecodableSiriusMessage) -> Void] = [:]
    private var pendingRequests: [UInt64: @Sendable (any DecodableSiriusMessage) -> Void] = [:]
    private var pendingAudioSessionRequests: [UUID: PendingAudioSessionRequest] = [:]

    private(set) var displayChangesSubscriptionID: UUID? = nil

    func setDisplayChangesSubscriptionID(_ id: UUID?) {
        displayChangesSubscriptionID = id
    }

    // MARK: - Session Operations

    func getSession(_ id: UUID) -> ProjectionSession? {
        sessions[id]
    }

    func setSession(_ id: UUID, _ session: ProjectionSession) {
        sessions[id] = session
    }

    @discardableResult
    func removeSession(_ id: UUID) -> ProjectionSession? {
        sessions.removeValue(forKey: id)
    }

    func removeAllSessions() -> [ProjectionSession] {
        let result = Array(sessions.values)
        sessions.removeAll()
        return result
    }

    // MARK: - Audio Session Operations

    func getAudioSession(_ id: UUID) -> AudioProjectionSession? {
        audioSessions[id]
    }

    func setAudioSession(_ id: UUID, _ session: AudioProjectionSession) {
        audioSessions[id] = session
    }

    @discardableResult
    func removeAudioSession(_ id: UUID) -> AudioProjectionSession? {
        audioSessions.removeValue(forKey: id)
    }

    func removeAllAudioSessions() -> [AudioProjectionSession] {
        let result = Array(audioSessions.values)
        audioSessions.removeAll()
        return result
    }

    // MARK: - Pending Session Operations

    func registerPendingSession(_ id: UUID, handler: @escaping @Sendable (any DecodableSiriusMessage) -> Void) {
        pendingSessions[id] = handler
    }

    @discardableResult
    func dispatchPendingSession(_ id: UUID, message: any DecodableSiriusMessage) -> Bool {
        guard let handler = pendingSessions.removeValue(forKey: id) else {
            return false
        }
        handler(message)
        return true
    }

    func removePendingSession(_ id: UUID) {
        pendingSessions.removeValue(forKey: id)
    }

    // MARK: - Pending Request Operations

    func registerPendingRequest(_ id: UInt64, handler: @escaping @Sendable (any DecodableSiriusMessage) -> Void) {
        pendingRequests[id] = handler
    }

    @discardableResult
    func dispatchPendingRequest(_ id: UInt64, message: any DecodableSiriusMessage) -> Bool {
        guard let handler = pendingRequests.removeValue(forKey: id) else {
            return false
        }
        handler(message)
        return true
    }

    func removePendingRequest(_ id: UInt64) {
        pendingRequests.removeValue(forKey: id)
    }

    // MARK: - Pending Audio Session Request Operations

    func registerPendingAudioSessionRequest(_ id: UUID, request: PendingAudioSessionRequest) {
        pendingAudioSessionRequests[id] = request
    }

    func hasPendingAudioSessionRequest(_ id: UUID) -> Bool {
        pendingAudioSessionRequests[id] != nil
    }

    @discardableResult
    func succeedPendingAudioSessionRequest(_ id: UUID, event: AudioSessionCreatedEvent) -> Bool {
        guard let pending = pendingAudioSessionRequests.removeValue(forKey: id) else {
            return false
        }
        pending.timeoutTask.cancel()
        pending.continuation.resume(returning: event)
        return true
    }

    @discardableResult
    func failPendingAudioSessionRequest(_ id: UUID, error: Error) -> Bool {
        guard let pending = pendingAudioSessionRequests.removeValue(forKey: id) else {
            return false
        }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: error)
        return true
    }

    func cancelAllPendingAudioSessionRequests(with error: Error = ProjectionChannelError.sessionCreationCancelled) {
        let pendingRequests = pendingAudioSessionRequests
        pendingAudioSessionRequests.removeAll()

        for (_, pending) in pendingRequests {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: error)
        }
    }
}
