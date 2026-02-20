//
//  SettingsXPCService.swift
//  noctilucad
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

/// noctilucad의 설정 XPC 서비스.
///
/// 별도의 Mach 서비스(``kNoctilucaSettingsMachServiceName``)를 통해
/// NoctilucaServer(Agent)에게 DaemonSettings 읽기/쓰기 및 AuthEntry CRUD 기능을 제공한다.
class SettingsXPCService: NSObject {
    private let logger = NoctilucaLogger(category: "SettingsXPCService")

    let listener: NSXPCListener
    private weak var daemon: NoctilucaDaemon?

    init(daemon: NoctilucaDaemon) {
        self.listener = NSXPCListener(machServiceName: kNoctilucaSettingsMachServiceName)
        self.daemon = daemon
        super.init()

        self.listener.delegate = self
    }

    func start() {
        logger.info("Starting settings XPC service on \(kNoctilucaSettingsMachServiceName)")
        listener.resume()
    }

    func stop() {
        listener.suspend()
    }
}

// MARK: - NSXPCListenerDelegate

extension SettingsXPCService: NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // 설정 XPC는 단방향(Agent → Daemon)이므로 remoteObjectInterface 불필요
        newConnection.exportedInterface = createSiriusDaemonSettingsXPCInterface()

        let handler = SettingsXPCHandler(daemon: daemon)
        newConnection.exportedObject = handler

        newConnection.resume()
        return true
    }
}

// MARK: - SettingsXPCHandler

/// SiriusDaemonSettingsXPCInterface의 실제 구현. 에이전트의 설정 관련 XPC 호출을 처리한다.
private class SettingsXPCHandler: NSObject, SiriusDaemonSettingsXPCInterface {
    private let logger = NoctilucaLogger(category: "SettingsXPCHandler")
    private weak var daemon: NoctilucaDaemon?

    /// SimplePasswordAuthPlugin의 method raw value.
    /// NoctilucaServer의 AuthMethod+NoctilucaServer.swift에서 정의된 값과 동일해야 한다.
    private static let simplePasswordMethodRawValue = "app.noctiluca.server.auth.simple-password"

    init(daemon: NoctilucaDaemon?) {
        self.daemon = daemon
    }

    // MARK: - General Settings

    func getSettings(reply: @escaping (NSData?, NSString?) -> Void) {
        guard let daemon else {
            reply(nil, "Daemon not available" as NSString)
            return
        }

        do {
            let settings = daemon.readSettings()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(settings)
            reply(data as NSData, nil)
        } catch {
            logger.error("getSettings failed: \(error.localizedDescription)")
            reply(nil, error.localizedDescription as NSString)
        }
    }

    func updateSettings(_ settingsData: NSData, reply: @escaping (Bool, NSString?) -> Void) {
        guard let daemon else {
            reply(false, "Daemon not available" as NSString)
            return
        }

        do {
            // 1. 수신된 JSON을 DaemonSettings로 디코딩
            var newSettings = try JSONDecoder().decode(
                DaemonSettings.self,
                from: settingsData as Data
            )

            // 2. 기존 allowedEntries를 보존 (JSON에 포함되지 않으므로 빈 배열로 디코딩됨)
            let existingEntries = daemon.readSettings().security.allowedEntries
            newSettings.security.allowedEntries = existingEntries

            // 3. 데몬에 적용 (저장 + 인메모리 갱신)
            try daemon.applySettings(newSettings)

            reply(true, nil)
        } catch {
            logger.error("updateSettings failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription as NSString)
        }
    }

    // MARK: - Auth Entry CRUD

    func getAuthEntries(reply: @escaping (NSArray?, NSString?) -> Void) {
        guard let daemon else {
            reply(nil, "Daemon not available" as NSString)
            return
        }

        let entries = daemon.readSettings().security.allowedEntries.map { entry in
            SiriusXPCRedactedAuthEntry(
                methodRawValue: entry.method.rawValue,
                identifier: entry.identifier
            )
        }

        reply(entries as NSArray, nil)
    }

    func addAuthEntry(
        methodRawValue: NSString,
        identifier: NSString,
        credential: NSData,
        reply: @escaping (Bool, NSString?) -> Void
    ) {
        guard let daemon else {
            reply(false, "Daemon not available" as NSString)
            return
        }

        let method = AuthMethod(rawValue: methodRawValue as String)
        let id = identifier as String
        let rawCredential = credential as Data

        Task {
            do {
                let hashedData: Data

                if method.rawValue == Self.simplePasswordMethodRawValue {
                    // SHA-512 + bcrypt 해싱 (SimplePasswordAuthPlugin의 검증 로직과 일치해야 함)
                    let digest = try await Bcrypt.sha512Async(value: rawCredential)
                    hashedData = try await Bcrypt.hashAsync(password: digest)
                } else {
                    // SSH 키 등 다른 method는 credential을 그대로 저장
                    hashedData = rawCredential
                }

                let entry = AuthEntry(
                    method: method,
                    identifier: id,
                    data: hashedData
                )

                try daemon.addAuthEntry(entry)
                reply(true, nil)
            } catch {
                self.logger.error("addAuthEntry failed: \(error.localizedDescription)")
                reply(false, error.localizedDescription as NSString)
            }
        }
    }

    func removeAuthEntry(
        methodRawValue: NSString,
        identifier: NSString,
        reply: @escaping (Bool, NSString?) -> Void
    ) {
        guard let daemon else {
            reply(false, "Daemon not available" as NSString)
            return
        }

        let method = AuthMethod(rawValue: methodRawValue as String)
        let id = identifier as String

        do {
            let removed = try daemon.removeAuthEntry(method: method, identifier: id)
            if removed {
                reply(true, nil)
            } else {
                reply(false, "No matching entry found" as NSString)
            }
        } catch {
            logger.error("removeAuthEntry failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription as NSString)
        }
    }
}
