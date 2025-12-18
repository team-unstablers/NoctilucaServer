//
//  NoctilucaClientApp.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

#if os(macOS)
import SwiftUI

@main
struct NoctilucaClientApp: App {
    @Environment(\.openWindow)
    var openWindow
    
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: NoctilucaMeta.scopedIdentifier("ui.window.settings"))
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)
        
        Window("Settings", id: NoctilucaMeta.scopedIdentifier("ui.window.settings")) {
            SettingsWindow()
        }
        .defaultLaunchBehavior(.suppressed)

    }
}
#endif
