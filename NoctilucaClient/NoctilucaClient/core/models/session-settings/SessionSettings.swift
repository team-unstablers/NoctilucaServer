//
//  SessionSettings.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import SiriusKitClient

enum SessionSettingsScope: String, Codable, Sendable, Hashable {
    case global
    case session
}

struct SessionSettings: Codable, Sendable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var scope: SessionSettingsScope = .global
    var general: General? = nil
    var projection: Projection = .init()
    var input: Input = .init()
    var security: Security = .init()
    var credentials: CredentialsRef = .init()

    init(
        scope: SessionSettingsScope = .global,
        general: General? = nil,
        projection: Projection = .init(),
        input: Input = .init(),
        security: Security = .init(),
        credentials: CredentialsRef = .init()
    ) {
        self.scope = scope
        self.general = general
        self.projection = projection
        self.input = input
        self.security = security
        self.credentials = credentials

        if self.credentials.keychainKey == nil, scope == .global {
            self.credentials.keychainKey = Self.credentialsKey(for: .global, contactId: nil)
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case scope
        case general
        case projection
        case input
        case security
        case credentials
    }

    init(from decoder: any Decoder) throws {
        self.init()

        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            return
        }

        schemaVersion = container.decodeSafe(Int.self, forKey: .schemaVersion, default: schemaVersion)
        scope = container.decodeSafe(SessionSettingsScope.self, forKey: .scope, default: scope)
        general = container.decodeSafeIfPresent(General.self, forKey: .general)
        projection = container.decodeSafe(Projection.self, forKey: .projection, default: projection)
        input = container.decodeSafe(Input.self, forKey: .input, default: input)
        security = container.decodeSafe(Security.self, forKey: .security, default: security)
        credentials = container.decodeSafe(CredentialsRef.self, forKey: .credentials, default: credentials)

        if credentials.keychainKey == nil, scope == .global {
            credentials.keychainKey = Self.credentialsKey(for: .global, contactId: nil)
        }
    }

    static func credentialsKey(for scope: SessionSettingsScope, contactId: UUID?) -> String? {
        switch scope {
        case .global:
            return NoctilucaMeta.scopedIdentifier("credentials.global")
        case .session:
            guard let contactId else { return nil }
            return NoctilucaMeta.scopedIdentifier("credentials.session.\(contactId.uuidString)")
        }
    }
}

extension SessionSettings {
    struct General: Codable, Sendable {
        var displayName: String = ""
        var endpoint: SREndpoint = SREndpoint(address: .hostname(""))
        var icon: ContactIcon = .init()

        enum CodingKeys: String, CodingKey {
            case displayName
            case endpoint
            case icon
        }

        init(
            displayName: String = "",
            endpoint: SREndpoint = SREndpoint(address: .hostname("")),
            icon: ContactIcon = .init()
        ) {
            self.displayName = displayName
            self.endpoint = endpoint
            self.icon = icon
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            displayName = (try? container.decode(String.self, forKey: .displayName)) ?? displayName
            icon = (try? container.decode(ContactIcon.self, forKey: .icon)) ?? icon

            // 하위 호환: 구 포맷 { "host": "...", "port": ... } 과 신 포맷 "host:port" 모두 처리
            if let srEndpoint = try? container.decode(SREndpoint.self, forKey: .endpoint) {
                endpoint = srEndpoint
            } else if let legacy = try? container.decode(LegacyEndpoint.self, forKey: .endpoint) {
                let port = legacy.port ?? SiriusQUICDefaultPort
                let host = legacy.host.trimmingCharacters(in: .whitespacesAndNewlines)
                if !host.isEmpty {
                    endpoint = SREndpoint.parse("\(host):\(port)")
                }
            }
        }
    }

    /// 구 포맷 마이그레이션용
    private struct LegacyEndpoint: Codable {
        var host: String = ""
        var port: UInt16? = nil
    }

    struct ContactIcon: Codable, Sendable {
        var symbol: ContactIconSymbol = .monitor
        var background: ContactIconBackground = .blue
    }

    enum ContactIconSymbol: String, Codable, CaseIterable, Sendable, Hashable {
        case monitor
        case laptop
        case server
        case terminal
        case gamepad
        case sparkles
        case gear
        case globe
    }

    enum ContactIconBackground: String, Codable, CaseIterable, Sendable, Hashable {
        case blue
        case green
        case orange
        case purple
        case gray
        case red
        case teal
        case yellow
    }
}

extension SessionSettings {
    enum CodecSettingsMode: String, Codable, Sendable, Hashable {
        case useDefault
        case manual
    }

    enum CodecNegotiationPolicy: String, Codable, Sendable, Hashable {
        case asOptional
        case asMandatory
    }
    
    struct Projection: Codable, Sendable {
        var codecSettingsMode: CodecSettingsMode = .useDefault
        var codecNegotiationPolicy: CodecNegotiationPolicy = .asOptional
        var codecSpecifications: [CodecSpecification] = [.hevc]
        
        var isAudioProjectionEnabled: Bool = true
        var audioCodecSpecifications: [AudioCodecSpecification] = [.opus]
    }
}

extension SessionSettings {
    struct Security: Codable, Sendable {
        var disableClientVersionAnnouncement: Bool = false
        var pinning: CertificatePinning? = nil
    }

    struct CertificatePinning: Codable, Sendable {
        var enabled: Bool = false
        var pinnedFingerprints: [CertificateFingerprint] = []
    }

    struct CertificateFingerprint: Codable, Sendable, Hashable {
        var algorithm: FingerprintAlgorithm = .sha256
        var value: String = ""
    }

    enum FingerprintAlgorithm: String, Codable, Sendable, Hashable {
        case sha256
    }
}

extension SessionSettings {
    struct Input: Codable, Sendable {
        var enabledKeyboardHacks: Set<String> = []
    }
}

extension SessionSettings {
    struct CredentialsRef: Codable, Sendable {
        var keychainKey: String? = nil
        var lastUpdatedAt: Date? = nil
    }
}

extension SessionSettings {
    mutating func ensureCredentialsKey(scope: SessionSettingsScope, contactId: UUID?) {
        if credentials.keychainKey != nil {
            return
        }

        credentials.keychainKey = Self.credentialsKey(for: scope, contactId: contactId)
    }
}

