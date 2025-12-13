//
//  AuthMethodEntry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import SwiftUI

import UniformTypeIdentifiers // UTType을 쓰기 위해 필요

import NoctilucaPluginKit

struct PluginBundleListEntry: View {
    let metadata: any PluginBundleMetadata
    
    var body: some View {
        HStack(alignment: .center) {
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading) {
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
            
            /*
            Spacer()
            
            Toggle(isOn: .constant(true)) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
             */
        }
        
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading) {
        /*
        AuthMethodEntry(method: .none)
        AuthMethodEntry(method: .password(allows: .user(name: "cheesekun")))
        AuthMethodEntry(method: .sshKey(publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz cheesekun@cheese-mbpr14.local"))
         */
    }
}
#endif
