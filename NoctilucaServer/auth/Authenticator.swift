//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation
import SiriusKit

class Authenticator {
    private let logger = NoctilucaLogger(category: "Authenticator")
    
    private let registry: AuthPluginRegistry
    private var plugins: [any AuthPlugin] = []
    
    init(registry: AuthPluginRegistry) {
        self.registry = registry
        
        logger.debug("init(): Authenticator initialized with \(registry.plugins.count) plugins")
    }
    
    deinit{
        self.demolish()
    }
    
    func demolish() {
        for plugin in self.plugins {
            do {
                try plugin.deinitialize()
            } catch {
                logger.error("demolish(): Failed to deinitialize plugin: \(type(of: plugin)) - \(error)")
            }
        }
        
        self.plugins.removeAll()
    }
    
    func setup() async {
        for pluginType in self.registry.plugins {
            let plugin = pluginType.init()
            do {
                try await plugin.initialize()
                self.plugins.append(plugin)
                logger.info("setup(): Initialized auth plugin: \(type(of: plugin))")
            } catch {
                logger.error("setup(): Failed to initialize auth plugin: \(type(of: plugin)) - \(error)")
            }
        }
    }
    
    func supportedMethods() -> Set<AuthMethod> {
        self.registry.plugins.reduce(into: Set<AuthMethod>()) { result, plugin in
            result.formUnion(plugin.supportedMethods)
        }
    }
    
    func authenticate(using method: AuthMethod, payload: consuming Data) async -> Result<uid_t, AuthError> {
        let LOG_TAG = "authenticate(using: \(method))"
        let supportedPlugins = self.plugins.filter { type(of: $0).supportedMethods.contains(method) }
        
        defer {
            _ = payload.withUnsafeMutableBytes { ptr in
                memset_s(ptr.baseAddress!, payload.count, 0, payload.count)
            }
        }

        // 순차적으로 dispatch한다.
        for supportedPlugin in supportedPlugins {
            logger.debug("\(LOG_TAG): trying plugin: \(type(of: supportedPlugin).name)")
            let result = await supportedPlugin.authenticate(using: method, payload: payload)
            
            if case .success(let uid) = result {
                logger.info("\(LOG_TAG): authentication succeeded using plugin: \(type(of: supportedPlugin).name), uid: \(uid)")
                return .success(uid)
            } else {
                logger.debug("\(LOG_TAG): authentication failed using plugin: \(type(of: supportedPlugin).name)")
            }
        }

        return .failure(.authenticationFailed)
    }
}

