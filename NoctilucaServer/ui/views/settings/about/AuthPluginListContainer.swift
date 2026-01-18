//
//  AuthMethodContainer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import AppKit
#if canImport(Collaboration)
import Collaboration
#endif
import SwiftUI

import NoctilucaPluginKit

struct AuthPluginListContainer: View {
    let registry = AuthPluginRegistry.shared
    
    let plugins: [any AuthPluginV1]
    @State
    private var selection = Set<String>()

    init() {
        self.plugins = Array(registry.plugins)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selection) {
                ForEach(plugins, id: \.id) { plugin  in
                    AuthPluginListEntry(plugin: plugin)
                        .tag(plugin.id)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        }
        
        if let selected = selection.first,
           let plugin = plugins.first(where: { $0.id == selected }) {
            AuthPluginDetailView(plugin: plugin)
        }
    }
}

struct AuthPluginDetailView: View {
    let plugin: any AuthPluginV1
    
    var body: some View {
        let metaType = type(of: plugin)
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metaType.name)
                    .font(.headline)
                
                Text("(\(metaType.id))")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            
            Text(metaType.description)
                .font(.subheadline)
        }
        
        SettingsEntry(title: String(localized: "settings.about.plugin.author", defaultValue: "개발자")) {
            VStack(alignment: .trailing) {
                ForEach(metaType.authors, id: \.self) { author in
                    Text(author)
                }
            }
            .foregroundStyle(.secondary)
        }

        SettingsEntry(title: String(localized: "settings.about.plugin.license", defaultValue: "라이선스")) {
            SoftwareLicenseText(license: metaType.license)
                .foregroundStyle(.secondary)
        }

        SettingsEntry(title: String(localized: "settings.about.plugin.type", defaultValue: "유형")) {
            if plugin is BuiltInAuthPluginV1 {
                Text(String(localized: "settings.about.plugin.type_builtin", defaultValue: "내장 플러그인"))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "settings.about.plugin.type_external", defaultValue: "외부 플러그인"))
                    .foregroundStyle(.secondary)
            }
        }

        SettingsEntry(title: String(localized: "settings.about.plugin.supported_methods", defaultValue: "지원하는 인증 메커니즘")) {
            VStack {
                ForEach(Array(metaType.supportedMethods), id: \.self) { method in
                    Text(method.rawValue)
                }
            }
            .foregroundStyle(.secondary)
        }

        SettingsEntry(title: String(localized: "settings.about.plugin.version", defaultValue: "버전")) {
            Text("\(metaType.displayVersion) (\(metaType.version))")
                .foregroundStyle(.secondary)
        }

    }
}
