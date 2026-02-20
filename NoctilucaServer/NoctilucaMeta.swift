//
//  NoctilucaServer+Meta.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation

import NoctilucaPluginKit

struct NoctilucaMeta {
    static var productName: String {
#if NOC_SERVER
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NoctilucaServer"
#endif
#if NOC_DAEMON
        return "noctilucad"
#endif
    }
    
    static var bundleIdentifier: String {
#if NOC_SERVER
        return Bundle.main.bundleIdentifier ?? "app.noctiluca.server"
#endif
#if NOC_DAEMON
        return "app.noctiluca.server.noctilucad"
#endif
    }
    
    static var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    
    static var license: SoftwareLicense = .proprietary(name: "Noctiluca Server EULA",
                                                       url: URL(string: "https://unstabler.pl")!)
    
}

extension NoctilucaMeta {
    static func scopedIdentifier(_ component: String) -> String {
        return "\(NoctilucaMeta.bundleIdentifier).\(component)"
    }
}

