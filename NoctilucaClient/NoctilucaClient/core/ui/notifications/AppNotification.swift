//
//  AppNotification.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/15/26.
//

import Foundation

import UserNotifications

enum AppNotificationCategory: String {
    case connectionEvents = "app.noctiluca.client.notification-events.connection"
    case sessionEvents    = "app.noctiluca.client.notification-events.session"
}

enum AppNotification: Identifiable {
    
    case backgroundSessionActive

    var id: String {
        switch self {
        case .backgroundSessionActive:
            return "background_sesion_active"
        }
    }

    var category: AppNotificationCategory {
        switch self {
        case .backgroundSessionActive:
            return .sessionEvents
        }
    }

    var title: String {
        // @claude, key로써는 `notification.{self}.title` 형태를 사용해 주세요
        switch self {
        case .backgroundSessionActive:
            return String(
                localized: "notification.background_session_active.title",
                defaultValue: "백그라운드 재생 중"
            )
        default:
            return ""
        }
    }

    var subtitle: String? {
        return nil
    }

    var message: String {
        // @claude, key로써는 `notification.{self}.message` 형태를 사용해 주세요
        switch self {
        case .backgroundSessionActive:
            return String(
                localized: "notification.background_session_active.message",
                defaultValue: "원격 세션의 오디오를 백그라운드에서 재생하고 있습니다."
            )
        default:
            return ""
        }
    }

    static func initialize() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("Failed to request notification authorization: \(error.localizedDescription)")
            }
        }
    }

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
            identifier: self.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to post notification \(self.id): \(error.localizedDescription)")
            }
        }
    }
    
    func dismiss() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [self.id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [self.id])
    }
}
