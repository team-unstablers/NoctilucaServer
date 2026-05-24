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
        /// 기본 마운트 포인트 경로. UI 의 "기본값으로 복원하기" 가 이 값을 사용합니다.
        static let defaultMountPointPath: String = "~/NoctilucaFS"

        /// fsaccess feature 활성화 여부. `false` 면 ServerHello.supportedFeatures 에서
        /// fsaccess UUID 가 빠지고, nocfsaccessd 데몬도 spawn 되지 않습니다.
        var enabled: Bool = false

        /// nocfsaccessd 의 가상 NFS 트리를 호스트 머신의 어디에 마운트할지.
        /// 기본값은 `~/NoctilucaFS`. 절대 경로 또는 `~/` 로 시작하는 경로 권장.
        var mountPointPath: String = FileAccess.defaultMountPointPath

        /// 자동 마운트 시 access mode. `true` 면 클라이언트 측의 쓰기 허용 여부와
        /// 무관하게 read-only 로 마운트합니다.
        var alwaysReadOnly: Bool = false

        /// `true` 면 navigator 가 `supportsLocks=true` 로 광고했더라도 host 측에서
        /// 강제로 false 로 다운그레이드해서 NFS LOCK / LOCKT / LOCKU callback 을
        /// 모두 fake success 로 응답합니다. exclusive access 를 강하게 요구하는
        /// 애플리케이션과 함께 사용할 때 오작동을 유발할 수 있어 기본값은 false
        /// (=navigator 광고 그대로 존중).
        var useFakeLocks: Bool = false

        /// `true` 면 host 가 mount setup 에서 `proposedCompressionMethods=[zstd, none]`
        /// 을 광고하고, navigator 가 zstd 를 골라 응답하면 inline read/write 와
        /// stream IO 의 데이터 플레인에 zstd 압축이 적용됩니다.
        /// `false` 면 빈 list 를 광고하여 navigator 측이 무조건 `none` 으로 답하도록
        /// 강제합니다. 기본값 `true` (NFS 트래픽 절감 우선).
        var enableCompression: Bool = true

        /// `true` 면 NFS WRITE 를 host 측 메모리에 일시 누적했다가 COMMIT / close
        /// / size 임계값 / idle 임계값 도달 시 한 번에 navigator wire 로 flush 한다.
        /// 작은 write 가 다발로 들어오는 패턴 (Excel/Word 등 office 앱 저장) 에서
        /// wire round-trip 횟수를 크게 줄여 체감 저장 속도를 개선한다.
        /// `false` 면 모든 WRITE 가 navigator 로 즉시 전달된다 (구버전 동작).
        /// 기본값 `true`. 토글 변경은 즉시 반영되며, 이미 누적된 dirty 데이터는
        /// 다음 COMMIT / close 에서 자연스럽게 flush 된다.
        var writeBackCacheEnabled: Bool = true

        init() {}

        enum CodingKeys: String, CodingKey {
            case enabled
            case mountPointPath
            case alwaysReadOnly
            case useFakeLocks
            case enableCompression
            case writeBackCacheEnabled
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
            alwaysReadOnly = container.decodeSafe(
                Bool.self, forKey: .alwaysReadOnly, default: alwaysReadOnly
            )
            useFakeLocks = container.decodeSafe(
                Bool.self, forKey: .useFakeLocks, default: useFakeLocks
            )
            enableCompression = container.decodeSafe(
                Bool.self, forKey: .enableCompression, default: enableCompression
            )
            writeBackCacheEnabled = container.decodeSafe(
                Bool.self, forKey: .writeBackCacheEnabled, default: writeBackCacheEnabled
            )
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(enabled, forKey: .enabled)
            try container.encode(mountPointPath, forKey: .mountPointPath)
            try container.encode(alwaysReadOnly, forKey: .alwaysReadOnly)
            try container.encode(useFakeLocks, forKey: .useFakeLocks)
            try container.encode(enableCompression, forKey: .enableCompression)
            try container.encode(writeBackCacheEnabled, forKey: .writeBackCacheEnabled)
        }
    }
}
