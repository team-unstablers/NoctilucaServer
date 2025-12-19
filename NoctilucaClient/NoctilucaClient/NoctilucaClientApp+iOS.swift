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
                Button("New Window") {
                    UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil, errorHandler: nil)
                }
                .keyboardShortcut("N", modifiers: [.command, .shift, .option])
            }
        }
        .commands {
            /*
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    mainUIViewModel.navState = [.settings]
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
             */
        }
    }
}
#endif
