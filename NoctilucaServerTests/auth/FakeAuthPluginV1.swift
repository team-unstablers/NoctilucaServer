//
//  FakeAuthPluginV1.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 4/25/26.
//

import Foundation

@preconcurrency import NoctilucaPluginKit

enum FakeAuthPluginError: Error, Equatable {
    case allowRejected
    case denyRejected
}

// actor 내부 mutable state를 reference wrapper로 감싸 actor의 stored property를
// `let` 하나만 두도록 만든다. 이렇게 해야 protocol `AuthPluginV1.init()` 요구사항과
// Swift 6의 "nonisolated synchronous init on actor" 제약이 충돌하지 않는다.
// wrapper 자체는 actor 격리 내부에서만 사용되므로 `@unchecked Sendable`이 안전하다.
private final class FakeAuthPluginState: @unchecked Sendable {
    var authenticateResult: Result<uid_t, AuthError> = .failure(.authenticationFailed(nil))
    var authenticateCalls: [(method: AuthMethod, payload: Data, nonce: Data)] = []
    var allowedEntries: [AuthEntry] = []
    var deniedEntries: [AuthEntry] = []
    var allowError: Error?
    var denyError: Error?
}

actor FakeAuthPluginV1A: AuthPluginV1 {
    static let id = "test.fake.auth.plugin.A"
    static let name = "FakeAuthPluginV1A"
    static let description = "Fake auth plugin for tests (supports .password)"
    static let authors = ["test@example.com"]
    static let license: SoftwareLicense = .mit
    static let version: UInt32 = 1
    static let displayVersion = "1.0"

    static let supportedMethods: Set<AuthMethod> = [.password]

    private let state = FakeAuthPluginState()

    var hasAllowedEntries: Bool {
        !state.allowedEntries.isEmpty
    }

    var authenticateResult: Result<uid_t, AuthError> { state.authenticateResult }
    var authenticateCalls: [(method: AuthMethod, payload: Data, nonce: Data)] { state.authenticateCalls }
    var allowedEntries: [AuthEntry] { state.allowedEntries }
    var deniedEntries: [AuthEntry] { state.deniedEntries }

    func setAuthenticateResult(_ result: Result<uid_t, AuthError>) {
        state.authenticateResult = result
    }

    func setAllowError(_ error: Error?) {
        state.allowError = error
    }

    func setDenyError(_ error: Error?) {
        state.denyError = error
    }

    func allow(_ entry: AuthEntry) async throws {
        if let error = state.allowError {
            throw error
        }
        state.allowedEntries.append(entry)
    }

    func deny(_ entry: AuthEntry) async throws {
        if let error = state.denyError {
            throw error
        }
        state.deniedEntries.append(entry)
    }

    func authenticate(using method: AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError> {
        let payloadCopy = payload.withUnsafeBytes { Data($0) }
        state.authenticateCalls.append((method: method, payload: payloadCopy, nonce: nonce))
        return state.authenticateResult
    }
}

actor FakeAuthPluginV1B: AuthPluginV1 {
    static let id = "test.fake.auth.plugin.B"
    static let name = "FakeAuthPluginV1B"
    static let description = "Fake auth plugin for tests (supports .sshKey)"
    static let authors = ["test@example.com"]
    static let license: SoftwareLicense = .mit
    static let version: UInt32 = 1
    static let displayVersion = "1.0"

    static let supportedMethods: Set<AuthMethod> = [.sshKey]

    private let state = FakeAuthPluginState()

    var hasAllowedEntries: Bool {
        !state.allowedEntries.isEmpty
    }

    var authenticateResult: Result<uid_t, AuthError> { state.authenticateResult }
    var authenticateCalls: [(method: AuthMethod, payload: Data, nonce: Data)] { state.authenticateCalls }
    var allowedEntries: [AuthEntry] { state.allowedEntries }
    var deniedEntries: [AuthEntry] { state.deniedEntries }

    func setAuthenticateResult(_ result: Result<uid_t, AuthError>) {
        state.authenticateResult = result
    }

    func setAllowError(_ error: Error?) {
        state.allowError = error
    }

    func setDenyError(_ error: Error?) {
        state.denyError = error
    }

    func allow(_ entry: AuthEntry) async throws {
        if let error = state.allowError {
            throw error
        }
        state.allowedEntries.append(entry)
    }

    func deny(_ entry: AuthEntry) async throws {
        if let error = state.denyError {
            throw error
        }
        state.deniedEntries.append(entry)
    }

    func authenticate(using method: AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError> {
        let payloadCopy = payload.withUnsafeBytes { Data($0) }
        state.authenticateCalls.append((method: method, payload: payloadCopy, nonce: nonce))
        return state.authenticateResult
    }
}
