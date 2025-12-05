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
import UniformTypeIdentifiers // UTType을 쓰기 위해 필요

import NoctilucaPluginKit

struct PluginBundleListContainer: View {
    init() {
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                HStack(alignment: .center) {
                    Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("SamplePlugin.bundle")
                                .font(.headline)
                            Text("(com.example.SamplePlugin)")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        Text("테스트를 위한 샘플 플러그인 모음집")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Toggle(isOn: .constant(true)) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        }
        
        PluginBundleDetailView()
    }
}

struct PluginBundleDetailView: View {
    var body: some View {
        HStack(alignment: .center) {
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("SamplePlugin.bundle")
                        .font(.headline)
                    
                    Text("(com.example.SamplePlugin)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                
                Text("테스트를 위한 샘플 플러그인 모음집")
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer()
            Button("정보 보기…") {
                
            }
        }
        
        HStack(alignment: .top) {
            Text("개발자")
            Spacer()
            VStack(alignment: .trailing) {
                Text(verbatim: "Kirino Kousaka <kiritan23@contoso.com>")
            }
            .foregroundStyle(.secondary)
        }
        
        HStack(alignment: .top) {
            Text("라이선스")
            Spacer()
            SoftwareLicenseText(license: .gplv3)
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
            Text("1.2.3 (10)")
                .foregroundStyle(.secondary)
        }

    }
}
