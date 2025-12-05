//
//  NoctilucaServer+Meta.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation

struct NoctilucaMeta {
    static var productName: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NoctilucaServer"
    }
    
    static var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "pl.unstabler.noctiluca.NoctilucaServer"
    }
    
    static var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
