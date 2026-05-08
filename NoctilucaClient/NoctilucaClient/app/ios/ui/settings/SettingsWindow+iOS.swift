//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/26/25.
//

#if os(iOS)

import SwiftUI

struct UIKitSettingsWindow: View {
    enum SettingsTab: Hashable {
        case general
        case projection
        case input
        case security
        case misc
        case plugins
        case about
    }

    let onSelectTab: (SettingsTab) -> Void

    var body: some View {
        Form {
            Section {
                Group {
                    Button(String(localized: "settings.tabs.general", defaultValue: "일반")) { onSelectTab(.general) }
                    Button(String(localized: "settings.tabs.projection", defaultValue: "프로젝션")) { onSelectTab(.projection) }
                    Button(String(localized: "settings.tabs.input", defaultValue: "입력")) { onSelectTab(.input) }
                    Button(String(localized: "settings.tabs.security", defaultValue: "보안")) { onSelectTab(.security) }
                    Button(String(localized: "settings.tabs.misc", defaultValue: "기타")) { onSelectTab(.misc) }
                    // Button(String(localized: "settings.tabs.plugins", defaultValue: "플러그인")) { onSelectTab(.plugins) }
                    Button(String(localized: "settings.tabs.about", defaultValue: "정보")) { onSelectTab(.about) }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(String(localized: "settings.title", defaultValue: "설정"))
    }
}

typealias SettingsWindow = UIKitSettingsWindow

#endif
