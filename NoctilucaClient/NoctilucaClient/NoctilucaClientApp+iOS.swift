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
    
    /*
    @NSApplicationDelegateAdaptor
    private var appDelegate: AppDelegate
     */

    var body: some Scene {
        WindowGroup {
            MobileUIMainView()
                .frame(minWidth: 480)
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
    }
}
#endif
