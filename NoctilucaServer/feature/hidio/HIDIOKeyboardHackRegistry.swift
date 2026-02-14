//
//  HIDIOKeyboardHackRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/14/26.
//

import NoctilucaPluginKit

class HIDIOKeyboardHackRegistry {
    static let shared = HIDIOKeyboardHackRegistry()
    
    private(set) var hacks: [String: KeyboardHackPluginV1] = [:]
    
    func register(_ plugin: KeyboardHackPluginV1) {
        self.hacks[type(of: plugin).id] = plugin
    }
    
    func unregister(_ id: String) {
        self.hacks.removeValue(forKey: id)
    }
}
