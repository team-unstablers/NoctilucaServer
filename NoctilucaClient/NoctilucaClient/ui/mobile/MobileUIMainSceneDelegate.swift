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
        
        rootViewController.mainWindowViewModel?.setInputFocusActive(false)
        rootViewController.mainWindowViewModel?.stopSession()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        rootViewController?.mainWindowViewModel?.setInputFocusActive(true)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        rootViewController?.mainWindowViewModel?.setInputFocusActive(false)
    }
}

#endif
