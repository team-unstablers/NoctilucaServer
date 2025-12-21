//
//  PluginsSettingsTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct PluginsSettingsTab: View {
    var body: some View {
        Form {
            Section {
                Text("준비 중입니다.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("플러그인")
            }
        }
        .formStyle(.grouped)
    }
}
