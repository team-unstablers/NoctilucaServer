//
//  PluginBundleDetailView.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

import SwiftUI
import UniformTypeIdentifiers // UTType을 쓰기 위해 필요

import NoctilucaPluginKit


struct PluginBundleDetailView: View {
    let metadata: any PluginBundleMetadata
    
    @State
    var showingInfoSheet = false
    
    var body: some View {
        HStack(alignment: .center) {
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(metadata.displayName)
                        .font(.headline)
                    
                    Text("(\(metadata.id))")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)

                Text(metadata.description)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer()
            Button(String(localized: "settings.plugins.detail.show_info", defaultValue: "정보 보기…")) {
                showingInfoSheet = true
            }
        }
        .sheet(isPresented: $showingInfoSheet) {
            PluginBundleDetailSheet(metadata: metadata) {
                showingInfoSheet = false
            }
        }
        
        SettingsEntry(title: String(localized: "settings.plugins.detail.developer", defaultValue: "개발자")) {
            VStack(alignment: .trailing) {
                ForEach(metadata.authors, id: \.self) { author in
                    Text(verbatim: author)
                }
            }
            .foregroundStyle(.secondary)
        }
        
        SettingsEntry(title: String(localized: "settings.plugins.detail.license", defaultValue: "라이선스")) {
            SoftwareLicenseText(license: metadata.license)
                .foregroundStyle(.secondary)
        }
        
        /*
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
         */
        
        SettingsEntry(title: String(localized: "settings.plugins.detail.signature", defaultValue: "서명 정보")) {
            Text("Apple Development: Kirino Kousaka (ABCDE12345)")
                .foregroundStyle(.secondary)
        }
        
        
        
        SettingsEntry(title: String(localized: "settings.plugins.detail.version", defaultValue: "버전")) {
            Text("\(metadata.displayVersion) (\(metadata.version))")
                .foregroundStyle(.secondary)
        }
    }
}
