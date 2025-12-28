//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if os(iOS) || os(tvOS)

import Foundation
import UIKit

import SiriusKitClient

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        SiriusLogger.configure(
            minimumLevel: .trace
        )
        
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        
        sceneConfig.delegateClass = MobileUIMainSceneDelegate.self
        
        return sceneConfig
    }
    
}

#endif
