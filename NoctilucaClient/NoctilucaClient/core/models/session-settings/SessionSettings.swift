//
//  SessionSettings.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

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
    var security: Security = .init()
    var credentials: CredentialsRef = .init()

    init(
        scope: SessionSettingsScope = .global,
        general: General? = nil,
        projection: Projection = .init(),
        security: Security = .init(),
        credentials: CredentialsRef = .init()
    ) {
        self.scope = scope
        self.general = general
        self.projection = projection
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
        var endpoint: Endpoint = .init()
        var icon: ContactIcon = .init()
    }

    struct Endpoint: Codable, Sendable {
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
        var tlsValidationPolicy: AppSettings.TLSValidationPolicy = .default
        var disableClientVersionAnnouncement: Bool = false
        var knownHost: KnownHostRecord? = nil
        var pinning: CertificatePinning? = nil
    }

    enum TrustDecision: String, Codable, Sendable, Hashable {
        case trustAlways
        case trustOnce
        case deny
        case ask
    }

    struct KnownHostRecord: Codable, Sendable {
        var fingerprint: CertificateFingerprint
        var trust: TrustDecision = .ask
        var firstSeenAt: Date? = nil
        var lastSeenAt: Date? = nil
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

extension SessionSettings.Endpoint {
    static func parse(_ endpointURL: String) -> SessionSettings.Endpoint {
        let parts = endpointURL.split(separator: ":")
        let host = String(parts.first ?? "")
        let port = UInt16(parts.dropFirst().first ?? "")

        return SessionSettings.Endpoint(host: host, port: port)
    }

    var urlString: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port else {
            return trimmedHost
        }

        if trimmedHost.isEmpty {
            return ""
        }

        return "\(trimmedHost):\(port)"
    }
}
