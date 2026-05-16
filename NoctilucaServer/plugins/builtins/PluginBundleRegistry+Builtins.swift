//
//  PluginBundleRegistry+CoreBundles.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//
import Foundation

extension PluginBundleRegistry {
    func registerBuiltinBundles() async throws {
        try await registerBundle(bundleClass: NoctilucaCoreAuth.self, manifest: NoctilucaCoreAuth.manifest)
    }
}
