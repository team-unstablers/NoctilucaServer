//
//  PluginBundleRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

class PluginBundleRegistry {
    static let shared = PluginBundleRegistry()
    private let logger = NoctilucaLogger(category: "PluginBundleRegistry")
    
    private init() {}
    
    func loadBundle(from url: URL) async throws {
        logger.info("Loading plugin bundle from \(url.path)")
        
        guard let bundle = Bundle(url: url) else {
            return
        }
        guard bundle.load() else {
            logger.error("Failed to load plugin bundle from \(url.path): unable to load bundle")
            return
        }
        
        guard let clazz = bundle.principalClass as? NoctilucaPluginBundle.Type else {
            logger.error("Failed to load plugin bundle from \(url.path): principal class is not a NoctilucaPluginBundle")
            return
        }
        
        
        try await clazz.initialize()
        
        for export in clazz.exports {
            switch export {
            case .auth(let plugin):
                logger.info("auth plugin found: \(plugin.id)")
                break
            @unknown default:
                break
            }
        }
        
        /*
        let instance = cls.init(context: context)
        let loaded = LoadedPlugin(bundle: bundle, type: cls, instance: instance)
        plugins.append(loaded)
        
        instance.activate()
         */
    }
    
}
