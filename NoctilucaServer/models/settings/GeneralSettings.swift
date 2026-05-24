//
//  GeneralSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct General: Category {
        /// 서버 자동 시작 여부
        var autoStart: Bool = true
        
        /// 최대 동시 접속 세션 수
        var maxConcurrentSessions: Int = 1

        init() {}

        enum CodingKeys: String, CodingKey {
            case autoStart
            case maxConcurrentSessions
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }
            
            autoStart = container.decodeSafe(Bool.self, forKey: .autoStart, default: autoStart)
            maxConcurrentSessions = container.decodeSafe(Int.self, forKey: .maxConcurrentSessions, default: maxConcurrentSessions)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(autoStart, forKey: .autoStart)
            try container.encode(maxConcurrentSessions, forKey: .maxConcurrentSessions)
        }
    }
    
    struct Notifications: Category {
        var enabled: Bool = false

        var onConnect: Bool = true
        var onDisconnect: Bool = true
        var onError: Bool = true
        var onClipboardAccess: Bool = false
        var onFileTransfer: Bool = true

        init() {}

        enum CodingKeys: String, CodingKey {
            case enabled
            case onConnect
            case onDisconnect
            case onError
            case onClipboardAccess
            case onFileTransfer
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enabled = container.decodeSafe(Bool.self, forKey: .enabled, default: enabled)
            onConnect = container.decodeSafe(Bool.self, forKey: .onConnect, default: onConnect)
            onDisconnect = container.decodeSafe(Bool.self, forKey: .onDisconnect, default: onDisconnect)
            onError = container.decodeSafe(Bool.self, forKey: .onError, default: onError)
            onClipboardAccess = container.decodeSafe(Bool.self, forKey: .onClipboardAccess, default: onClipboardAccess)
            onFileTransfer = container.decodeSafe(Bool.self, forKey: .onFileTransfer, default: onFileTransfer)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
            try container.encode(onConnect, forKey: .onConnect)
            try container.encode(onDisconnect, forKey: .onDisconnect)
            try container.encode(onError, forKey: .onError)
            try container.encode(onClipboardAccess, forKey: .onClipboardAccess)
            try container.encode(onFileTransfer, forKey: .onFileTransfer)
        }
    }
}
