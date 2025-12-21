//
//  SecuritySettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    enum TLSValidationPolicy: String, Codable, CaseIterable, Sendable {
        case unsafe
        case `default`
        case strict

        init(from decoder: any Decoder) throws {
            let container = try? decoder.singleValueContainer()
            let rawValue = (try? container?.decode(String.self)) ?? Self.default.rawValue
            self = TLSValidationPolicy(rawValue: rawValue) ?? .default
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    struct Security: SecureCategory {
        var tlsValidationPolicy: TLSValidationPolicy = .default
        var disableClientVersionAnnouncement: Bool = false

        init() {}

        enum CodingKeys: String, CodingKey {
            case tlsValidationPolicy
            case disableClientVersionAnnouncement
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            tlsValidationPolicy = container.decodeSafe(TLSValidationPolicy.self, forKey: .tlsValidationPolicy, default: tlsValidationPolicy)
            disableClientVersionAnnouncement = container.decodeSafe(
                Bool.self,
                forKey: .disableClientVersionAnnouncement,
                default: disableClientVersionAnnouncement
            )
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tlsValidationPolicy, forKey: .tlsValidationPolicy)
            try container.encode(disableClientVersionAnnouncement, forKey: .disableClientVersionAnnouncement)
        }

        func saveSecureEntries() throws {
        }

        mutating func loadSecureEntries() throws {
        }
    }
}
