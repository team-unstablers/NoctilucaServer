//
//  AuthPluginRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

class AuthPluginRegistry {
    private(set) public var plugins: [AuthPlugin.Type] = []
    
    func register(plugin: AuthPlugin.Type) {
        if plugins.contains(where: { $0.name == plugin.name }) {
            return
        }
        
        plugins.append(plugin)
    }
    
    func unregister(plugin: AuthPlugin.Type) {
        plugins.removeAll(where: { $0.name == plugin.name })
    }
    
    func unregisterAll() {
        plugins.removeAll()
    }
}
