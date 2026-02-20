//
//  SecuritySettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

extension DaemonSettings {
    struct Security: SecureCategory {
        private static let KEY_ALLOWED_ENTRIES = "app.noctiluca.server.settings.security.allowedEntries"
        
        var allowedEntries: [AuthEntry] = []
        var maxLoginAttempts: Int = 3
        var pluginBundleSecurityPolicy: PluginBundleSecurityPolicy = .allowTeamUnstablers

        enum CodingKeys: String, CodingKey {
            // allowedEntries는 보안 항목이므로 인코딩/디코딩 시 제외
            case maxLoginAttempts
            case pluginBundleSecurityPolicy
        }
        
        init() {
            
        }
        
        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            maxLoginAttempts = container.decodeSafe(Int.self, forKey: .maxLoginAttempts, default: maxLoginAttempts)
            pluginBundleSecurityPolicy = container.decodeSafe(PluginBundleSecurityPolicy.self, forKey: .pluginBundleSecurityPolicy, default: pluginBundleSecurityPolicy)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(maxLoginAttempts, forKey: .maxLoginAttempts)
            try container.encode(pluginBundleSecurityPolicy, forKey: .pluginBundleSecurityPolicy)
        }
        
#if NOC_DAEMON
        func saveSecureEntries(scope: DaemonScope) throws {
            try saveSecureEntry(allowedEntries, forKey: Self.KEY_ALLOWED_ENTRIES)
        }
        
        mutating func loadSecureEntries(scope: DaemonScope) throws {
            allowedEntries = (try loadSecureEntry(forKey: Self.KEY_ALLOWED_ENTRIES, as: [AuthEntry].self)) ?? []
        }
#endif
    }
    
    /// 트랜스포트 레이어
    struct Transport: Category {
        var implementation: String = "msquic"
        
        /// 서버 버전을 알리지 않기
        /// - 서버 버전을 클라이언트에게 알리지 않는다.
        /// - 보안성이 강화될 수 있을지도 모르지만.. 호환성이 떨어질 수 있다.
        var disableServerVersionAnnouncement: Bool = false
        
        /// 지원하는 기능 목록을 알리지 않기
        /// - 서버가 지원하는 기능 목록을 클라이언트에게 알리지 않는다.
        /// - 보안성이 강화될 수 있을지도 모르지만.. 호환성이 떨어질 수 있다.
        var disableSupportedFeaturesAnnouncement: Bool = false
        
        var motd: String = ""
        var authChallengeMessage: String = ""

        init() {}

        enum CodingKeys: String, CodingKey {
            case implementation
            case disableServerVersionAnnouncement
            case disableSupportedFeaturesAnnouncement
            case motd
            case authChallengeMessage
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }
            
            implementation = container.decodeSafe(String.self, forKey: .implementation, default: implementation)
            
            disableServerVersionAnnouncement = container.decodeSafe(
                Bool.self,
                forKey: .disableServerVersionAnnouncement,
                default: disableServerVersionAnnouncement
            )
            disableSupportedFeaturesAnnouncement = container.decodeSafe(
                Bool.self,
                forKey: .disableSupportedFeaturesAnnouncement,
                default: disableSupportedFeaturesAnnouncement
            )
            motd = container.decodeSafe(String.self, forKey: .motd, default: motd)
            authChallengeMessage = container.decodeSafe(String.self, forKey: .authChallengeMessage, default: authChallengeMessage)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(implementation, forKey: .implementation)
            try container.encode(disableServerVersionAnnouncement, forKey: .disableServerVersionAnnouncement)
            try container.encode(disableSupportedFeaturesAnnouncement, forKey: .disableSupportedFeaturesAnnouncement)
            try container.encode(motd, forKey: .motd)
            try container.encode(authChallengeMessage, forKey: .authChallengeMessage)
        }
    }
    
    struct QUICTransport: Category {
        var listenPort: UInt16 = SiriusQUICDefaultPort
        
        /// 자동 구성된 TLS 설정 사용하기
        /// - true 설정 시 자가 서명 인증서를 자동으로 발급하여 사용한다
        /// - 인증서 만료 시 갱신, 분실 시 재발급 등을 자동으로 처리한다
        var tlsUseAutoconf: Bool = true {
            didSet {
                if tlsStrictValidation {
                    tlsStrictValidation = false
                }
                
                if tlsUseAutoconf {
                    do {
                        try self.autoconfigureIdentity()
                    } catch {
                        DaemonSettings.logger.error("Failed to auto-configure QUIC identity: \(error.localizedDescription)")
                        tlsUseAutoconf = false
                    }
                } else {
                    identity = nil
                }
            }
        }
        
        /// 엄격한 유효성 검사 사용하기
        /// - 시스템의 트러스트 스토어를 기준으로 인증서가 신뢰 가능한지 엄격하게 검사한다
        ///   (= self-signed 인증서나 신뢰할 수 없는 CA에서 발급한 인증서를 사용하여 서버 가동 시도 시 실패하도록 한다)
        var tlsStrictValidation: Bool = false
        
        /// 서버 TLS 인증서 및 개인 키 설정
        /// - TODO: assert(tlsUseAutoconf && identity.type != .pemFile)
        var identity: TLSIdentity? = nil

        init() {}

        enum CodingKeys: String, CodingKey {
            case listenPort
            case tlsUseAutoconf
            case tlsStrictValidation
            case identity
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            listenPort = container.decodeSafe(UInt16.self, forKey: .listenPort, default: listenPort)
            tlsUseAutoconf = container.decodeSafe(Bool.self, forKey: .tlsUseAutoconf, default: tlsUseAutoconf)
            tlsStrictValidation = container.decodeSafe(Bool.self, forKey: .tlsStrictValidation, default: tlsStrictValidation)
            identity = (try? container.decodeIfPresent(TLSIdentity.self, forKey: .identity)) ?? identity
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(listenPort, forKey: .listenPort)
            try container.encode(tlsUseAutoconf, forKey: .tlsUseAutoconf)
            try container.encode(tlsStrictValidation, forKey: .tlsStrictValidation)
            try container.encodeIfPresent(identity, forKey: .identity)
        }
    }
}

extension DaemonSettings.QUICTransport {
    mutating func autoconfigureIdentity() throws {
        guard tlsUseAutoconf else {
            return
        }
        
        /*
        // 아이덴티티를 새로 만들자!
        AppSettings.logger.info("Creating new auto-configured identity...")
        
        let hostname = hostname()
        let commonName = "Noctiluca Server: self-signed server identity (\(hostname))"
        self.identity = .keychain(identifier: commonName)
        
        // 아이덴티티를 매번 새로 생성하게 함 -- 하기 try-catch에서 재생성 시도할 때 이 부분을 타야 함
        // if (!(try KeychainQUICServerIdentity.checkIdentityExistance(label: commonName))) {
        AppSettings.logger.info("Creating self-signed identity with label: \(commonName)...")
        
        let args = QUICServerIdentityCreationArgs(
            // identityLabel하고 commonName이 같지 않으면 생성에 실패함
            identityLabel: commonName,
            commonName: commonName,
            organizationName: "Noctiluca Server",
            organizationalUnitName: "Auto-configured Identity",
            countryName: "KR",
            validityPeriodInDays: 365
        )
        
        _ = try KeychainQUICServerIdentity.createSelfSignedIdentity(args: args)
        // }
         */
    }
}
