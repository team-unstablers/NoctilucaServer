//
//  MobileUISceneDelegate.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

#if canImport(UIKit)
import Foundation
import UIKit

import SwiftUI

class MobileUIMainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    var rootViewController: RootViewController? {
        return window?.rootViewController as? RootViewController
    }

    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            
            let controller = RootViewController()
            window.rootViewController = controller

            self.window = window
            window.makeKeyAndVisible()
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        guard let rootViewController = rootViewController else {
            return
        }
        
        Task { @MainActor in
            await rootViewController.mainWindowViewModel?.stopSession()
        }
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        if DeviceKind.current == .iPhone {
            if NOCAudioEngine.shared.activeNodes != 0 {
                AppNotification.backgroundSessionActive.post()
            }
        }
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        if DeviceKind.current == .iPhone {
            AppNotification.backgroundSessionActive.dismiss()
        }
    }
}

#endif
