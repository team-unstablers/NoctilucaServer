//
//  ServerNotification.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/27/25.
//

import Foundation

import UserNotifications

enum AppNotificationCategory: String {
    case clientEvents = "noctiluca.client.events"
    case serverEvents = "noctiluca.server.events"
    case licenseEvents = "noctiluca.license.events"
    case updateEvents = "noctiluca.update.events"
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
        }
    }
    
    var title: String {
        switch self {
        case .newConnection:
            return "새 클라이언트 연결됨"
        case .connectionClosed:
            return "클라이언트 연결 종료됨"
        case .serverStarted:
            return "서버 시작됨"
        case .serverStartFailed:
            return "서버 시작 실패"
        case .serverStopped:
            return "서버 종료됨"
        case .tlsAutoconfRenewed:
            return "인증서 자동 갱신 성공"
        case .invalidLicense:
            return "부정한 라이선스"
        case .updateAvailable:
            return "새 업데이트 사용 가능"
        case .criticalUpdateRequired:
            return "긴급 업데이트 필요"
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
        switch self {
        case .newConnection:
            return "새 클라이언트가 서버에 연결되었습니다."
        case .connectionClosed:
            return "클라이언트 연결이 종료되었습니다."
        case .serverStarted:
            return "서버가 성공적으로 시작되었습니다."
        case .serverStartFailed(let error):
            return "서버 시작 중 오류가 발생했습니다: \(error.localizedDescription)"
        case .serverStopped:
            return "서버가 종료되었습니다."
        case .tlsAutoconfRenewed:
            return "TLS 인증서가 자동으로 갱신되었습니다."
        case .invalidLicense:
            return "부정한 라이선스가 감지되었습니다.\n정식 버전 구매를 고려해 주세요."
        case .updateAvailable(let version):
            return "새 버전 \(version)이(가) 사용 가능합니다."
        case .criticalUpdateRequired(let version, let isInvalidLicense):
            var message = "심각한 보안 문제가 발견되어 버전 \(version)으로의 긴급 업데이트가 필요합니다."
            if isInvalidLicense {
                message += "\n이 업데이트는 불법 복제본 사용자에게도 제공됩니다. 업데이트를 긍정적으로 고려해 주세요."
            }
            
            return message
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
