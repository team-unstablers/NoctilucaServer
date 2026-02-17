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
        
        if let activityType = options.userActivities.first?.activityType {
            let sceneConfig = UISceneConfiguration(
                name: nil,
                sessionRole: connectingSceneSession.role
            )
            
            sceneConfig.delegateClass = AboutAppWindowUISceneDelegate.self
            
            return sceneConfig
        } else {
            let sceneConfig = UISceneConfiguration(
                name: nil,
                sessionRole: connectingSceneSession.role
            )
            
            sceneConfig.delegateClass = MobileUIMainSceneDelegate.self
            
            return sceneConfig
        }
    }
}

#endif
