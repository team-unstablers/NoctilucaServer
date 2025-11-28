//
//  NoctilucaServerApp.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/20/25.
//

import SwiftUI

@main
struct NoctilucaServerApp: App {
    @StateObject
    var server = NoctilucaServer.shared
    
    var body: some Scene {
        WindowGroup {
            SettingsWindow()
        }
        
        MenuBarExtra("My App", systemImage: "star.fill") {
            MainTrayMenuContents()
                .environmentObject(server)
        }
        // 스타일 지정이 핵심 (.menu 또는 .window)
        .menuBarExtraStyle(.menu)
    }
}
