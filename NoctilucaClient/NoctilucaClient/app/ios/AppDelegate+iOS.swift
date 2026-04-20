//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if os(iOS)

import Foundation
import UIKit

import SiriusKitClient

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // ignore SIGPIPE to prevent app from crashing when trying to write to a closed socket
        signal(SIGPIPE, SIG_IGN);
        
        SiriusLogger.configure(
            minimumLevel: .trace
        )
        
        AppNotification.initialize()
        AddressMonitor.shared.start()
        
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // userActivity.activityType 으로 어떤 역할의 scene 인지 식별한다.
        // - "app.noctiluca.client.about"      → AboutAppWindowUISceneDelegate
        // - "app.noctiluca.client.sub-display" → SubDisplayUISceneDelegate (iPadOS 멀티 디스플레이)
        // - 그 외(nil 포함)                    → MobileUIMainSceneDelegate (메인 연결 창)
        let activityType = options.userActivities.first?.activityType
            ?? connectingSceneSession.stateRestorationActivity?.activityType

        let delegateClass: AnyClass
        switch activityType {
        case "app.noctiluca.client.about":
            delegateClass = AboutAppWindowUISceneDelegate.self
        case SubDisplayCoordinator.activityType:
            delegateClass = SubDisplayUISceneDelegate.self
        default:
            delegateClass = MobileUIMainSceneDelegate.self
        }

        let sceneConfig = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        sceneConfig.delegateClass = delegateClass
        return sceneConfig
    }
}

#endif
