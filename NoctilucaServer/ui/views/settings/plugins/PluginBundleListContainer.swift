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
            EditableList(
                items: .constant(Array(pluginRegistry.bundles.values)),
                id: \.manifest.id,
                selection: $selection,
                rowContent: { handle in
                    PluginBundleListEntry(manifest: handle.manifest)
                }
            )

            if let selected = selection.first,
               let handle = pluginRegistry.bundles[selected]
            {
                PluginBundleDetailView(handle: handle, signingResult: handle.signingResult)
            }
        }
    }
}

