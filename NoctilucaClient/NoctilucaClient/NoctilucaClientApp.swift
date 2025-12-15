//
//  NoctilucaClientApp.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

import SwiftUI

@main
struct NoctilucaClientApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
#if os(macOS)
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)
#endif
        
    }
}
