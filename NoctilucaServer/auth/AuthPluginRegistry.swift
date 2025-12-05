//
//  AuthPluginRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

class AuthPluginRegistry {
    private(set) public var plugins: [AuthPluginV1] = []
    
    func register(plugin: AuthPluginV1) {
        if plugins.contains(where: { $0.id == $0.id }) {
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
