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
                .lineLimit(1)
        }
        
        HStack(alignment: .top) {
            Text("개발자")
            Spacer()
            VStack(alignment: .trailing) {
                ForEach(metaType.authors, id: \.self) { author in
                    Text(author)
                }
            }
            .foregroundStyle(.secondary)
        }
        
        HStack(alignment: .top) {
            Text("라이선스")
            Spacer()
            SoftwareLicenseText(license: metaType.license)
                .foregroundStyle(.secondary)
        }
        
        HStack(alignment: .top) {
            Text("유형")
            Spacer()
            if plugin is BuiltInAuthPluginV1 {
                Text("내장 플러그인")
                    .foregroundStyle(.secondary)
            } else {
                Text("외부 플러그인")
                    .foregroundStyle(.secondary)
            }
        }
        
        HStack(alignment: .top) {
            Text("지원하는 인증 매커니즘")
            Spacer()
            VStack {
                ForEach(Array(metaType.supportedMethods), id: \.self) { method in
                    Text(method.rawValue)
                }
            }
            .foregroundStyle(.secondary)
        }
        
        HStack(alignment: .top) {
            Text("버전")
            Spacer()
            Text("\(metaType.displayVersion) (\(metaType.version))")
                .foregroundStyle(.secondary)
        }

    }
}
