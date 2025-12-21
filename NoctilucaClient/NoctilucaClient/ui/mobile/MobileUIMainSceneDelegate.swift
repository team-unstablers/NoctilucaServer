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
    
    /// FIXME: 둘이 합치던가 하세요
    var mainUIViewModel: MobileUIMainViewModel? = nil
    var mainWindowViewModel: MainWindowViewModel? = nil
    var settingsStore: SettingsStore? = nil
    var sessionSettingsStore: SessionSettingsStore? = nil
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let mainUIViewModel = MobileUIMainViewModel()
        let mainWindowViewModel = MainWindowViewModel()
        let settingsStore = SettingsStore()
        let sessionSettingsStore = SessionSettingsStore()
        
        self.mainUIViewModel = mainUIViewModel
        self.mainWindowViewModel = mainWindowViewModel
        self.settingsStore = settingsStore
        self.sessionSettingsStore = sessionSettingsStore
        
        let contentView = MobileUIMainView()
            .environmentObject(mainUIViewModel)
            .environmentObject(mainWindowViewModel)
            .environmentObject(settingsStore)
            .environmentObject(sessionSettingsStore)
        
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        mainWindowViewModel?.stopSession()
    }
}

#endif
