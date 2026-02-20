//
//  DaemonSettingsXPCClient.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import SiriusKit

import NoctilucaPluginKit

// MARK: - Error

enum DaemonSettingsXPCError: LocalizedError {
    case connectionFailed
    case remoteError(String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "XPC connection to settings service failed"
        case .remoteError(let msg):
            return "Settings XPC error: \(msg)"
        case .decodingFailed(let error):
            return "Failed to decode settings: \(error.localizedDescription)"
        }
    }
}

// MARK: - RedactedAuthEntry

/// XPC에서 수신한 SiriusXPCRedactedAuthEntry를 Swift-native 타입으로 변환한 구조체.
struct RedactedAuthEntry: Sendable, Hashable {
    let method: AuthMethod
    let identifier: String
}

// MARK: - DaemonSettingsXPCClient

/// noctilucad의 설정 XPC 서비스에 연결하여 DaemonSettings를 읽고 쓰는 클라이언트.
///
/// NSXPCConnection을 lazy하게 생성하며, invalidation 시 자동으로 재연결한다.
/// 모든 공개 메서드는 async로 제공되어 Swift Concurrency와 자연스럽게 통합된다.
class DaemonSettingsXPCClient {
    private let logger = NoctilucaLogger(category: "DaemonSettingsXPCClient")
    private let machServiceName: String
    private var connection: NSXPCConnection?

    init(machServiceName: String = kNoctilucaSettingsMachServiceName) {
        self.machServiceName = machServiceName
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    private func ensureConnection() -> NSXPCConnection {
        if let conn = connection {
            return conn
        }

        let conn = NSXPCConnection(machServiceName: machServiceName)
        conn.remoteObjectInterface = createSiriusDaemonSettingsXPCInterface()

        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }

        conn.interruptionHandler = { [weak self] in
            self?.logger.warning("Settings XPC connection interrupted")
            self?.connection = nil
        }

        conn.resume()
        self.connection = conn
        return conn
    }

    private func getProxy() throws -> SiriusDaemonSettingsXPCInterface {
        let conn = ensureConnection()

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.logger.error("Settings XPC proxy error: \(error.localizedDescription)")
        }) as? SiriusDaemonSettingsXPCInterface else {
            throw DaemonSettingsXPCError.connectionFailed
        }

        return proxy
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Settings Read/Write

    /// DaemonSettings 전체를 조회한다.
    ///
    /// Security.allowedEntries는 포함되지 않는다 (CodingKeys에서 제외).
    func getSettings() async throws -> DaemonSettings {
        let proxy = try getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getSettings { data, errorDesc in
                if let errorDesc = errorDesc as? String {
                    continuation.resume(throwing: DaemonSettingsXPCError.remoteError(errorDesc))
                    return
                }

                guard let data = data as? Data else {
                    continuation.resume(throwing: DaemonSettingsXPCError.remoteError("No data returned"))
                    return
                }

                do {
                    let settings = try JSONDecoder().decode(DaemonSettings.self, from: data)
                    continuation.resume(returning: settings)
                } catch {
                    continuation.resume(throwing: DaemonSettingsXPCError.decodingFailed(error))
                }
            }
        }
    }

    /// DaemonSettings 전체를 업데이트한다.
    ///
    /// AuthEntry 변경은 이 메서드가 아닌 전용 AuthEntry CRUD 메서드를 사용해야 한다.
    func updateSettings(_ settings: DaemonSettings) async throws {
        let proxy = try getProxy()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(settings)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.updateSettings(data as NSData) { success, errorDesc in
                if success {
                    continuation.resume()
                } else {
                    let msg = (errorDesc as? String) ?? "Unknown error"
                    continuation.resume(throwing: DaemonSettingsXPCError.remoteError(msg))
                }
            }
        }
    }

    // MARK: - Auth Entry CRUD

    /// 등록된 모든 AuthEntry를 redacted 형태로 조회한다.
    ///
    /// 반환되는 엔트리에는 보안 데이터(해시, 키)가 포함되지 않는다.
    func getAuthEntries() async throws -> [RedactedAuthEntry] {
        let proxy = try getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getAuthEntries { array, errorDesc in
                if let errorDesc = errorDesc as? String {
                    continuation.resume(throwing: DaemonSettingsXPCError.remoteError(errorDesc))
                    return
                }

                guard let xpcEntries = array as? [SiriusXPCRedactedAuthEntry] else {
                    continuation.resume(returning: [])
                    return
                }

                let entries = xpcEntries.map { xpcEntry in
                    RedactedAuthEntry(
                        method: AuthMethod(rawValue: xpcEntry.methodRawValue),
                        identifier: xpcEntry.identifier
                    )
                }
                continuation.resume(returning: entries)
            }
        }
    }

    /// 새 AuthEntry를 추가한다.
    ///
    /// 데몬이 method에 따라 credential을 해싱한 후 Keychain에 저장한다.
    /// - Parameters:
    ///   - method: 인증 방식
    ///   - identifier: 엔트리 식별자 (e.g. "bcrypt+sha512")
    ///   - credential: 평문 credential 데이터
    func addAuthEntry(method: AuthMethod, identifier: String, credential: Data) async throws {
        let proxy = try getProxy()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.addAuthEntry(
                methodRawValue: method.rawValue as NSString,
                identifier: identifier as NSString,
                credential: credential as NSData
            ) { success, errorDesc in
                if success {
                    continuation.resume()
                } else {
                    let msg = (errorDesc as? String) ?? "Unknown error"
                    continuation.resume(throwing: DaemonSettingsXPCError.remoteError(msg))
                }
            }
        }
    }

    /// AuthEntry를 제거한다.
    ///
    /// - Parameters:
    ///   - method: 인증 방식
    ///   - identifier: 엔트리 식별자
    func removeAuthEntry(method: AuthMethod, identifier: String) async throws {
        let proxy = try getProxy()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.removeAuthEntry(
                methodRawValue: method.rawValue as NSString,
                identifier: identifier as NSString
            ) { success, errorDesc in
                if success {
                    continuation.resume()
                } else {
                    let msg = (errorDesc as? String) ?? "Unknown error"
                    continuation.resume(throwing: DaemonSettingsXPCError.remoteError(msg))
                }
            }
        }
    }
}
