//
//  AuthPluginRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

class AuthPluginRegistry {
    static let shared = initShared()
    
    private static func initShared() -> AuthPluginRegistry {
        let registry = AuthPluginRegistry()
        
        // Register built-in plugins
        registry.register(plugin: PAMAuthPlugin())
        
#if DEBUG
        registry.register(plugin: NullAuthPlugin())
#endif
        
        return registry
    }
    
    private(set) public var plugins: [AuthPluginV1] = []
    
    func register(plugin: AuthPluginV1) {
        if plugins.contains(where: { $0 === plugin }) {
            return
        }
        
        plugins.append(plugin)
    }
    
    func unregister(plugin: AuthPluginV1) {
        plugins.removeAll { $0 === plugin }
    }
    
    func unregisterAll() {
        plugins.removeAll()
    }
}
