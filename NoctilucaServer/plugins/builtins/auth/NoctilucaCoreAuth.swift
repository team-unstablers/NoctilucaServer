//
//  NoctilucaCoreAuth.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

@preconcurrency import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

final class NoctilucaCoreAuth: NoctilucaPluginBundle {
    static let manifest = BuiltinPluginBundleManifest(
        id: "app.noctiluca.server.bundles.NoctilucaCoreAuth",
        name: NSLocalizedString("builtin-bundles.auth.NoctilucaCoreAuth.name", comment: "Noctiluca 기본 인증 플러그인 번들"),
        bundleDescription: NSLocalizedString("builtin-bundles.auth.NoctilucaCoreAuth.description", comment: "Noctiluca의 기본 인증 플러그인 번들입니다."),
        authors: [
            "Gyuhwan Park <unstabler@unstabler.pl>"
        ],
        license: NoctilucaMeta.license,
        pluginKitVersion: .v1,
        exports: [
            PAMAuthPlugin.manifest,
            SimplePasswordAuthPlugin.manifest
        ]
    )

    static func initialize() async throws {
        
    }
    
    static func deinitialize() throws {
        
    }
    
    static let exports: [NoctilucaPluginExport] = [
        .auth(PAMAuthPlugin()),
        .auth(SSHAuthPlugin()),
        .auth(SimplePasswordAuthPlugin()),
    ]
    
    static let supportedActions: [NoctilucaPluginBundleAction] = []
    
    static func dispatchAction(action: NoctilucaPluginBundleAction) async throws {
        
    }
}
