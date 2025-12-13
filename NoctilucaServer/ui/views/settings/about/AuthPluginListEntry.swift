//
//  AuthMethodEntry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import SwiftUI

import NoctilucaPluginKit

struct AuthPluginListEntry: View {
    let plugin: any AuthPluginV1
    
    var body: some View {
        let metaType = type(of: plugin)
        
        VStack(alignment: .leading) {
            HStack {
                Text(metaType.name)
                    .font(.headline)
                /*
                Text("(\(metaType.id))")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                 */
            }
                .lineLimit(1)
            Text(metaType.description)
                .font(.subheadline)
                .lineLimit(1)
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
