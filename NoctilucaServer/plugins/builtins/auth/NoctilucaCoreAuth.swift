//
//  NoctilucaCoreAuth.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

import NoctilucaPluginKit

class NoctilucaCoreAuth: NoctilucaPluginBundle {
    static let metadata = BuiltinPluginBundleMetadata(
        id: "app.noctiluca.server.bundles.NoctilucaCoreAuth",
        displayName: NSLocalizedString("builtin-bundles.auth.NoctilucaCoreAuth.name", comment: "Noctiluca 기본 인증 플러그인 번들"),
        
        version: 1,
        displayVersion: NoctilucaMeta.version,
        
        pluginKitVersion: .v1,
        description: NSLocalizedString("builtin-bundles.auth.NoctilucaCoreAuth.description", comment: "Noctiluca의 기본 인증 플러그인 번들입니다."),
        
        authors: [
            "Gyuhwan Park <unstabler@unstabler.pl>"
        ],
        license: NoctilucaMeta.license,
        
        exports: [
            PAMAuthPlugin.metadata,
            SimplePasswordAuthPlugin.metadata
        ]
    )
    
    static let name = NSLocalizedString("builtin-bundles.auth.NoctilucaCoreAuth.name", comment: "Noctiluca 기본 인증 플러그인 번들")
    static let description = NSLocalizedString("builtin-bundles.auth.NoctilucaCoreAuth.description", comment: "Noctiluca의 기본 인증 플러그인 번들입니다.")
    
    static func initialize() async throws {
        
    }
    
    static func deinitialize() throws {
        
    }
    
#if DEBUG
    static var exports: [NoctilucaPluginExport] = [
        .auth(PAMAuthPlugin()),
        .auth(SimplePasswordAuthPlugin()),
        .auth(SSHAuthPlugin()),
        .auth(NullAuthPlugin())
    ]
#else
    static var exports: [NoctilucaPluginExport] = [
        .auth(PAMAuthPlugin()),
        .auth(SSHAuthPlugin()),
        .auth(SimplePasswordAuthPlugin()),
    ]
#endif
}
