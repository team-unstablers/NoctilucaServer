//
//  MainTrayMenu.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/29/25.
//

import SwiftUI

enum MainTrayMenuAction: Sendable {
    case openSettingsWindow
    case quitApplication
}

struct MainTrayMenuContents: View {
    let actionHandler: (MainTrayMenuAction) -> Void
    
    @EnvironmentObject
    var server: NoctilucaServer
    
    var body: some View {
        Button(String(localized: "menu.session.none", defaultValue: "현재 활성 중인 세션 없음")) {

        }
        .disabled(true)

        if case .running(_) = server.state {
            Button(String(localized: "menu.server.stop", defaultValue: "서버 중지")) {
                Task {
                    do {
                        try await server.shutdown()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        } else {
            Button(String(localized: "menu.server.start", defaultValue: "서버 시작")) {
                Task {
                    do {
                        try await server.startup()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        }
        Divider()
        Button(String(localized: "menu.settings", defaultValue: "설정")) {
            actionHandler(.openSettingsWindow)
        }
        Divider()
        Button(String(localized: "menu.quit", defaultValue: "종료")) {
            actionHandler(.quitApplication)
        }
    }
}
