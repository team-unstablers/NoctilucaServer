//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

class Authenticator {
    private let logger = NoctilucaLogger(category: "Authenticator")
    
    private let registry: AuthPluginRegistry
    private var plugins: [AuthPluginV1] {
        registry.plugins
    }
    
    init(registry: AuthPluginRegistry) {
        self.registry = registry
        
        logger.debug("init(): Authenticator initialized with \(registry.plugins.count) plugins")
    }
    
    func supportedMethods() -> Set<NoctilucaPluginKit.AuthMethod> {
        self.registry.plugins.reduce(into: Set<NoctilucaPluginKit.AuthMethod>()) { result, plugin in
            result.formUnion(type(of: plugin).supportedMethods)
        }
    }
    
    func supports(method: NoctilucaPluginKit.AuthMethod) -> Bool {
        self.plugins.contains { type(of: $0).supportedMethods.contains(method) }
    }
    
    func authenticate(using method: NoctilucaPluginKit.AuthMethod, payload: consuming Data) async -> Result<uid_t, AuthError> {
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

        return .failure(.authenticationFailed(nil))
    }
}

