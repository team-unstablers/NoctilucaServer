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

        init() {}

        enum CodingKeys: String, CodingKey {
            case enabled
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enabled = container.decodeSafe(Bool.self, forKey: .enabled, default: enabled)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
        }
    }
}
