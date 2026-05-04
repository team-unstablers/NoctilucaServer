//
//  FileAccessSettings.swift
//  NoctilucaServer
//

import Foundation

/// 호스트 앱이 navigator 의 fsaccess entries 를 자기 머신에 어떻게 마운트할지의 정책.
///
/// 호스트는 fsaccess 의 **consuming peer** 이므로, 본 enum 은
/// "노출할 폴더를 누구에게 보일지" 가 아니라 *받은 entries 중 어느 것을 자동으로
/// Mount 할지* 의 정책을 표현합니다. 실제 사용자 consent prompt 는 navigator 측
/// (`FSAccessConsentBroker`) 이 책임집니다.
enum HostFSAccessConsentPolicy: String, Codable, Sendable, CaseIterable, Hashable {
    /// List 응답을 받으면 사용자에게 알림으로 선택지를 제시한 뒤 Mount.
    case alwaysAsk
    /// connect 직후 모든 entry 를 즉시 자동 Mount (read-write).
    case alwaysAllow
    /// 자동 Mount 하되, requestedAccess 를 read-only 로 강제.
    case alwaysAllowReadOnly
    /// 어떤 entry 도 Mount 하지 않음 (control channel 자체를 열지 않음).
    case deny
}

extension AppSettings {
    /// File System Access (fsaccess) 기능의 호스트 측 정책.
    struct FileAccess: Category {
        /// fsaccess feature 활성화 여부. `false` 면 ServerHello.supportedFeatures 에서
        /// fsaccess UUID 가 빠지고, nocfsaccessd 데몬도 spawn 되지 않습니다.
        var enabled: Bool = false

        /// nocfsaccessd 의 가상 NFS 트리를 호스트 머신의 어디에 마운트할지.
        /// 기본값은 `~/NoctilucaFS`. 절대 경로 또는 `~/` 로 시작하는 경로 권장.
        var mountPointPath: String = "~/NoctilucaFS"

        /// allowedConnections 에 매칭되지 않는 navigator connection 에 적용할 기본 정책.
        var defaultConsentPolicy: HostFSAccessConsentPolicy = .alwaysAsk

        init() {}

        enum CodingKeys: String, CodingKey {
            case enabled
            case mountPointPath
            case defaultConsentPolicy
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enabled = container.decodeSafe(Bool.self, forKey: .enabled, default: enabled)
            mountPointPath = container.decodeSafe(
                String.self, forKey: .mountPointPath, default: mountPointPath
            )
            defaultConsentPolicy = container.decodeSafe(
                HostFSAccessConsentPolicy.self,
                forKey: .defaultConsentPolicy,
                default: defaultConsentPolicy
            )
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(enabled, forKey: .enabled)
            try container.encode(mountPointPath, forKey: .mountPointPath)
            try container.encode(defaultConsentPolicy, forKey: .defaultConsentPolicy)
        }
    }
}
