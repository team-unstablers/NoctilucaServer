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

final class TestViewController: UIHostingController<AnyView> {
    var isPointerLocked: Bool = false {
        didSet {
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }
    
    override var prefersPointerLocked: Bool {
        return isPointerLocked
    }
}

class MobileUIMainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    /// FIXME: 둘이 합치던가 하세요
    var mainUIViewModel: MobileUIMainViewModel? = nil
    var mainWindowViewModel: MainWindowViewModel? = nil
    var settingsStore: SettingsStore? = nil
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let mainUIViewModel = MobileUIMainViewModel()
        let mainWindowViewModel = MainWindowViewModel()
        let settingsStore = SettingsStore()
        
        self.mainUIViewModel = mainUIViewModel
        self.mainWindowViewModel = mainWindowViewModel
        self.settingsStore = settingsStore
        
        let contentView = MobileUIMainView()
            .environmentObject(mainUIViewModel)
            .environmentObject(mainWindowViewModel)
            .environmentObject(settingsStore)
               
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            
            let controller = TestViewController(rootView: AnyView(contentView))
            window.rootViewController = controller

            self.window = window
            window.makeKeyAndVisible()
            
            controller.isPointerLocked = true
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        mainWindowViewModel?.stopSession()
    }
}

#endif
