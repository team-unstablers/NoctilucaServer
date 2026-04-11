//
//  NoctilucaServer+Meta.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation

@preconcurrency import NoctilucaPluginKit

struct NoctilucaMeta {
    static var productName: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NoctilucaServer"
    }
    
    static var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "app.noctiluca.server"
    }
    
    static var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    
    static let license: SoftwareLicense = .proprietary(name: "Noctiluca Server EULA",
                                                       url: URL(string: "https://unstabler.pl")!)
    
}

extension NoctilucaMeta {
    static func scopedIdentifier(_ component: String) -> String {
        return "\(NoctilucaMeta.bundleIdentifier).\(component)"
    }
}

