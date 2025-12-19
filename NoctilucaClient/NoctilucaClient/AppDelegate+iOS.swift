//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if os(iOS)

import Foundation
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
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
