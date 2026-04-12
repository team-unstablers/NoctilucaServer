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
    var clipboard: Clipboard = .init()
    var transfer: Transfer = .init()
    var security: Security = .init()
    var credentials: CredentialsRef = .init()

    init(
        scope: SessionSettingsScope = .global,
        general: General? = nil,
        projection: Projection = .init(),
        input: Input = .init(),
        clipboard: Clipboard = .init(),
        transfer: Transfer = .init(),
        security: Security = .init(),
        credentials: CredentialsRef = .init()
    ) {
        self.scope = scope
        self.general = general
        self.projection = projection
        self.input = input
        self.clipboard = clipboard
        self.transfer = transfer
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
        case clipboard
        case transfer
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
        clipboard = container.decodeSafe(Clipboard.self, forKey: .clipboard, default: clipboard)
        transfer = container.decodeSafe(Transfer.self, forKey: .transfer, default: transfer)
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
        var codecSpecifications: [CodecSpecification] = [.hevc, .h264, .vp8]
        
        var isAudioProjectionEnabled: Bool = true
        var audioCodecSpecifications: [AudioCodecSpecification] = [.opus, .pcmu, .pcma]
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
    struct Clipboard: Codable, Sendable {
        /// 클립보드 공유 기능 활성화 여부
        var enabled: Bool = true

        /// 텍스트 데이터만 허용할지 여부
        var textOnly: Bool = false

        /// 파일 복사 허용 여부
        var allowFile: Bool = false

        /// iOS: 양방향 클립보드 동기화 사용 여부
        /// false인 경우 서버→클라이언트 방향만 동기화됩니다.
        var useBidirectionalSync: Bool = false

        init() {}

        enum CodingKeys: String, CodingKey {
            case enabled
            case textOnly
            case allowFile
            case useBidirectionalSync
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enabled = container.decodeSafe(Bool.self, forKey: .enabled, default: enabled)
            textOnly = container.decodeSafe(Bool.self, forKey: .textOnly, default: textOnly)
            allowFile = container.decodeSafe(Bool.self, forKey: .allowFile, default: allowFile)
            useBidirectionalSync = container.decodeSafe(Bool.self, forKey: .useBidirectionalSync, default: useBidirectionalSync)
        }
    }
}

extension SessionSettings {
    struct Transfer: Codable, Sendable {
        /// Zstd 압축 사용 여부
        var enableCompression: Bool = false

        init() {}

        enum CodingKeys: String, CodingKey {
            case enableCompression
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableCompression = container.decodeSafe(Bool.self, forKey: .enableCompression, default: enableCompression)
        }
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

