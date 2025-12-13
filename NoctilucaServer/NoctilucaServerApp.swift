//
//  NoctilucaServerApp.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/20/25.
//

import SwiftUI

@main
struct NoctilucaServerApp: App {
    @NSApplicationDelegateAdaptor
    private var appDelegate: AppDelegate
    
    @StateObject
    var server = NoctilucaServer.shared
    
    @Environment(\.openWindow)
    private var openWindow
    
    private let settingsWindowID = "pl.unstabler.noctiluca.NoctilucaServer.SettingsWindow"
    
    var body: some Scene {
        Window("Noctiluca Server 설정", id: settingsWindowID) {
            SettingsWindow()
                .environmentObject(server)
        }
        .defaultLaunchBehavior(.suppressed)
        
        /*
        Window("test", id: "test") {
            CodecSpecificationSheet()
        }
        .defaultLaunchBehavior(.presented)
         */
        
        MenuBarExtra("My App", systemImage: "star.fill") {
            MainTrayMenuContents { action in
                handleMenuAction(action)
            }
                .environmentObject(server)
        }
        // 스타일 지정이 핵심 (.menu 또는 .window)
        .menuBarExtraStyle(.menu)
    }

    func handleMenuAction(_ action: MainTrayMenuAction) {
        switch action {
        case .openSettingsWindow:
            openWindow(id: settingsWindowID)
            NSApp.activate(ignoringOtherApps: true)
        case .quitApplication:
            // TODO: 세션 있는 경우 confirm 받고 종료할 것
            NSApp.terminate(nil)
        }
    }
}
