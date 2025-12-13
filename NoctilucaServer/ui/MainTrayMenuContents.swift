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
        Button("현재 활성 중인 세션 없음") {
            
        }
        .disabled(true)
        
        if case .running(_) = server.state {
            Button("서버 중지") {
                Task {
                    do {
                        try await server.shutdown()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        } else {
            Button("서버 시작") {
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
        Button("설정") {
            actionHandler(.openSettingsWindow)
        }
        Divider()
        Button("종료") {
            actionHandler(.quitApplication)
        }
    }
}
