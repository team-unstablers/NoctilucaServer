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
    
    @NSApplicationDelegateAdaptor
    private var appDelegate: AppDelegate

    @StateObject
    private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(settingsStore)
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
                .environmentObject(settingsStore)
        }
        .defaultLaunchBehavior(.suppressed)

    }
}
#endif
