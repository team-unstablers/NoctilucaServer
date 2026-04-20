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

struct PendingDisplayTransaction: Sendable {
    let continuation: CheckedContinuation<DisplayTransactionResponse, Error>
    let timeoutTask: Task<Void, Never>
}

/// ProjectionChannel의 mutable state를 actor isolation으로 보호합니다.
actor ProjectionChannelState {
    typealias PendingHandler = @Sendable (Result<any DecodableSiriusMessage, Error>) -> Void

    var sessions: [UUID: ProjectionSession] = [:]
    var audioSessions: [UUID: AudioProjectionSession] = [:]

    private var pendingSessions: [UUID: PendingHandler] = [:]
    private var pendingRequests: [UInt64: PendingHandler] = [:]
    private var pendingAudioSessionRequests: [UUID: PendingAudioSessionRequest] = [:]
    private var pendingDisplayTransactions: [UUID: PendingDisplayTransaction] = [:]

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

    func registerPendingSession(_ id: UUID, handler: @escaping PendingHandler) {
        pendingSessions[id] = handler
    }

    @discardableResult
    func dispatchPendingSession(_ id: UUID, message: any DecodableSiriusMessage) -> Bool {
        guard let handler = pendingSessions.removeValue(forKey: id) else {
            return false
        }
        handler(.success(message))
        return true
    }

    @discardableResult
    func failPendingSession(_ id: UUID, error: Error) -> Bool {
        guard let handler = pendingSessions.removeValue(forKey: id) else {
            return false
        }
        handler(.failure(error))
        return true
    }

    func removePendingSession(_ id: UUID) {
        pendingSessions.removeValue(forKey: id)
    }

    func cancelAllPendingSessions(with error: Error = ProjectionChannelError.channelClosed) {
        let pending = pendingSessions
        pendingSessions.removeAll()
        for (_, handler) in pending {
            handler(.failure(error))
        }
    }

    // MARK: - Pending Request Operations

    func registerPendingRequest(_ id: UInt64, handler: @escaping PendingHandler) {
        pendingRequests[id] = handler
    }

    @discardableResult
    func dispatchPendingRequest(_ id: UInt64, message: any DecodableSiriusMessage) -> Bool {
        guard let handler = pendingRequests.removeValue(forKey: id) else {
            return false
        }
        handler(.success(message))
        return true
    }

    @discardableResult
    func failPendingRequest(_ id: UInt64, error: Error) -> Bool {
        guard let handler = pendingRequests.removeValue(forKey: id) else {
            return false
        }
        handler(.failure(error))
        return true
    }

    func removePendingRequest(_ id: UInt64) {
        pendingRequests.removeValue(forKey: id)
    }

    func cancelAllPendingRequests(with error: Error = ProjectionChannelError.channelClosed) {
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, handler) in pending {
            handler(.failure(error))
        }
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

    // MARK: - Pending Display Transaction Operations

    func registerPendingDisplayTransaction(_ id: UUID, request: PendingDisplayTransaction) {
        pendingDisplayTransactions[id] = request
    }

    func hasPendingDisplayTransaction(_ id: UUID) -> Bool {
        pendingDisplayTransactions[id] != nil
    }

    @discardableResult
    func succeedPendingDisplayTransaction(_ id: UUID, response: DisplayTransactionResponse) -> Bool {
        guard let pending = pendingDisplayTransactions.removeValue(forKey: id) else {
            return false
        }
        pending.timeoutTask.cancel()
        pending.continuation.resume(returning: response)
        return true
    }

    @discardableResult
    func failPendingDisplayTransaction(_ id: UUID, error: Error) -> Bool {
        guard let pending = pendingDisplayTransactions.removeValue(forKey: id) else {
            return false
        }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: error)
        return true
    }

    func cancelAllPendingDisplayTransactions(with error: Error = ProjectionChannelError.channelClosed) {
        let pending = pendingDisplayTransactions
        pendingDisplayTransactions.removeAll()

        for (_, request) in pending {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}
