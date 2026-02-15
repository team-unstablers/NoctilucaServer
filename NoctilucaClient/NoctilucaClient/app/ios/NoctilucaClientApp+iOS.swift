//
//  NoctilucaClientApp.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

#if os(iOS)
import SwiftUI

@main
struct NoctilucaClientApp: App {
    
    @UIApplicationDelegateAdaptor
    private var appDelegate: AppDelegate
    
    var body: some Scene {
        WindowGroup {
            // @see MobileUIMainSceneDelegate.swift
            EmptyView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.new_window", defaultValue: "새 윈도우")) {
                    UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil, errorHandler: nil)
                }
                .keyboardShortcut("N", modifiers: [.command, .shift, .option])
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "menu.settings", defaultValue: "Noctiluca Navigator 설정…")) {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "menu.about", defaultValue: "Noctiluca Navigator에 대하여")) {
                    UIApplication.shared.requestSceneSessionActivation(
                        nil,
                        userActivity: NSUserActivity(activityType: "app.noctiluca.client.about"),
                        options: nil,
                        errorHandler: nil
                    )
                }
            }
        }
    }
    
    func openSettings() {
        // 연결된 scene 중 가장 첫번째의 루트 뷰 컨트롤러에 접근하여 설정 화면을 엽니다.
        guard let firstScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else {
            return
        }
        
        guard let window = firstScene.windows.first(where: { $0.rootViewController is RootViewController }),
              let rootViewController = window.rootViewController as? RootViewController
        else {
            return
        }
        
        rootViewController.mainUIViewModel?.navState = [.settings]
    }
}
#endif
    
