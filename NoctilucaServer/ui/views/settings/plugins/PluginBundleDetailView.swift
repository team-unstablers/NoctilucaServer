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
            Button("정보 보기…") {
                showingInfoSheet = true
            }
        }
        .sheet(isPresented: $showingInfoSheet) {
            PluginBundleDetailSheet(metadata: metadata) {
                showingInfoSheet = false
            }
        }
        
        HStack(alignment: .top) {
            Text("개발자")
            Spacer()
            VStack(alignment: .trailing) {
                ForEach(metadata.authors, id: \.self) { author in
                    Text(verbatim: author)
                }
            }
            .foregroundStyle(.secondary)
        }
        
        HStack(alignment: .top) {
            Text("라이선스")
            Spacer()
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
        
        HStack(alignment: .top) {
            Text("서명 정보")
            Spacer()
            Text("Apple Development: Kirino Kousaka (ABCDE12345)")
                .foregroundStyle(.secondary)
        }
        
        
        
        HStack(alignment: .top) {
            Text("버전")
            Spacer()
            Text("\(metadata.displayVersion) (\(metadata.version))")
                .foregroundStyle(.secondary)
        }
    }
}

