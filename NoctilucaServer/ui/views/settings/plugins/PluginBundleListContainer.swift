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

struct PluginBundleListContainer: View {
    let pluginRegistry = PluginBundleRegistry.shared
    
    @State
    private var selection = Set<String>()

    init() {
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selection) {
                ForEach(Array(pluginRegistry.bundles.values), id: \.metadata.id) { handle in
                    let metadata = handle.metadata
                    PluginBundleListEntry(metadata: metadata)
                        .tag(metadata.id)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        }
        
        if let selected = selection.first,
           let handle = pluginRegistry.bundles[selected]
        {
            PluginBundleDetailView(metadata: handle.metadata)
        }
    }
}

