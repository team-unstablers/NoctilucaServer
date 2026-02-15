//
//  ServerNotification.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/27/25.
//

import Foundation

import UserNotifications

enum AppNotificationCategory: String {
    case clientEvents  = "app.noctiluca.server.notification-events.client"
    case serverEvents  = "app.noctiluca.server.notification-events.server"
    case licenseEvents = "app.noctiluca.server.notification-events.license"
    case updateEvents  = "app.noctiluca.server.notification-events.update"
    case securityEvents = "app.noctiluca.server.notification-events.security"
}

enum AppNotification: Identifiable {
    // TODO: 새 연결 생성
    case newConnection(endpoint: String)
    // TODO: 연결 종료
    case connectionClosed(endpoint: String)
    
    // TODO: 서버 시작
    case serverStarted
    // TODO: 서버 시작 시 오류 발생
    case serverStartFailed(error: Error)
    // TODO: 서버 종료
    case serverStopped
    // TODO: 인증서 자동 갱신 성공
    case tlsAutoconfRenewed
    // TODO: 부정한 라이선스
    case invalidLicense
    // TODO: 라이선스 만료 임박
    // TODO: 라이선스 만료
    // TODO: 새 업데이트 사용 가능
    case updateAvailable(version: String)
    // TODO: 긴급 업데이트 요청
    case criticalUpdateRequired(version: String, isInvalidLicense: Bool)
    case pluginBundleRejectedBySecurityPolicy(metadata: any PluginBundleMetadata, currentPolicy: PluginBundleSecurityPolicy)
    
    var id: String {
        switch self {
        case .newConnection:
            return "new_connection"
        case .connectionClosed:
            return "connection_closed"
        case .serverStarted:
            return "server_started"
        case .serverStartFailed:
            return "server_start_failed"
        case .serverStopped:
            return "server_stopped"
        case .tlsAutoconfRenewed:
            return "tls_autoconf_renewed"
        case .invalidLicense:
            return "invalid_license"
        case .updateAvailable:
            return "update_available"
        case .criticalUpdateRequired:
            return "critical_update_required"
        case .pluginBundleRejectedBySecurityPolicy:
            return "plugin_bundle_rejected_by_security_policy"
        }
    }
    
    var category: AppNotificationCategory {
        switch self {
        case .newConnection, .connectionClosed:
            return .clientEvents
        case .serverStarted, .serverStartFailed, .serverStopped, .tlsAutoconfRenewed:
            return .serverEvents
        case .invalidLicense:
            return .licenseEvents
        case .updateAvailable, .criticalUpdateRequired:
            return .updateEvents
        case .pluginBundleRejectedBySecurityPolicy:
            return .securityEvents
        }
    }
    
    var title: String {
        // @claude, key로써는 `notification.{self}.title` 형태를 사용해 주세요
        switch self {
        case .newConnection:
            return String(localized: "notification.new_connection.title", defaultValue: "새 클라이언트 연결됨")
        case .connectionClosed:
            return String(localized: "notification.connection_closed.title", defaultValue: "클라이언트 연결 종료됨")
        case .serverStarted:
            return String(localized: "notification.server_started.title", defaultValue: "서버 시작됨")
        case .serverStartFailed:
            return String(localized: "notification.server_start_failed.title", defaultValue: "서버 시작 실패")
        case .serverStopped:
            return String(localized: "notification.server_stopped.title", defaultValue: "서버 종료됨")
        case .tlsAutoconfRenewed:
            return String(localized: "notification.tls_autoconf_renewed.title", defaultValue: "인증서 자동 갱신 성공")
        case .invalidLicense:
            return String(localized: "notification.invalid_license.title", defaultValue: "부정한 라이선스")
        case .updateAvailable:
            return String(localized: "notification.update_available.title", defaultValue: "새 업데이트 사용 가능")
        case .criticalUpdateRequired:
            return String(localized: "notification.critical_update_required.title", defaultValue: "긴급 업데이트 필요")
        case .pluginBundleRejectedBySecurityPolicy:
            return String(localized: "notificaiton.plugin_bundle_rejected_by_security_policy.title", defaultValue: "플러그인 번들 로드 거부됨")
        }
    }
    
    var subtitle: String? {
        switch self {
        case .newConnection(let endpoint):
            return endpoint
        case .connectionClosed(let endpoint):
            return endpoint
            
        default:
            return nil
        }
    }
    
    var message: String {
        // @claude, key로써는 `notification.{self}.message` 형태를 사용해 주세요
        switch self {
        case .newConnection:
            return String(localized: "notification.new_connection.message", defaultValue: "새 클라이언트가 서버에 연결되었습니다.")
        case .connectionClosed:
            return String(localized: "notification.connection_closed.message", defaultValue: "클라이언트 연결이 종료되었습니다.")
        case .serverStarted:
            return String(localized: "notification.server_started.message", defaultValue: "서버가 성공적으로 시작되었습니다.")
        case .serverStartFailed(let error):
            return String(format: String(localized: "notification.server_start_failed.message", defaultValue: "서버 시작 중 오류가 발생했습니다: %@"), error.localizedDescription)
        case .serverStopped:
            return String(localized: "notification.server_stopped.message", defaultValue: "서버가 종료되었습니다.")
        case .tlsAutoconfRenewed:
            return String(localized: "notification.tls_autoconf_renewed.message", defaultValue: "TLS 인증서가 자동으로 갱신되었습니다.")
        case .invalidLicense:
            return String(localized: "notification.invalid_license.message", defaultValue: "부정한 라이선스가 감지되었습니다.\n정식 버전 구매를 고려해 주세요.")
        case .updateAvailable(let version):
            return String(format: String(localized: "notification.update_available.message", defaultValue: "새 버전 %@이(가) 사용 가능합니다."), version)
        case .criticalUpdateRequired(let version, let isInvalidLicense):
            var message = String(format: String(localized: "notification.critical_update_required.message", defaultValue: "심각한 보안 문제가 발견되어 버전 %@으로의 긴급 업데이트가 필요합니다."), version)
            if isInvalidLicense {
                message += "\n" + String(localized: "notification.critical_update_required.piracy_notice.message", defaultValue: "이 업데이트는 불법 복제본 사용자에게도 제공됩니다. 업데이트를 긍정적으로 고려해 주세요.")
            }

            return message
        case .pluginBundleRejectedBySecurityPolicy(let metadata, let currentPolicy):
            return String(
                format: String(
                    localized: "notification.plugin_bundle_rejected_by_security_policy.message",
                    defaultValue: "플러그인 번들 '%@'이 코드 서명 정책을 위반하여 로드될 수 없었습니다."
                ),
                metadata.id
            )
        }
        
    }
    
    @MainActor
    func post() {
        let content = UNMutableNotificationContent()
        content.title = self.title
        content.body = self.message
        content.sound = .default
        content.categoryIdentifier = self.category.rawValue
        content.interruptionLevel = .active
        
        if let subtitle = self.subtitle {
            content.subtitle = subtitle
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to post notification \(self.id): \(error.localizedDescription)")
            }
        }
    }
}
