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


struct PluginBundleDetailSheet: View {
    let metadata: any PluginBundleMetadata
    
    let dismissAction: () -> Void
    
    var body: some View {
        TabView() {
            Text("test")
                .tabItem {
                    Text("기본")
                }
            Text("test2")
                .tabItem {
                    Text("서명")
                }
        }
        .with {
            if #available(macOS 15.0, *) {
                $0.tabViewStyle(.grouped)
            } else {
                #warning("macOS 15.0 아래 버전에서 탭 표시 동작을 확인해야 합니다")
                $0
            }
        }
    }
}

