//
//  AppSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/27/25.
//

import Foundation

struct AppSettings: Codable, Sendable {
    // MARK: - General Settings
    
    var general: General = .init()
    var notifications: Notifications = .init()
    
    // MARK: - Security Settings
    
    var security: Security = .init()
    var transport: Transport = .init()
    var quicTransport: QUICTransport = .init()
    
    // MARK: - Misc Settings
    
    var telemetry: Telemetry = .init()
}

extension AppSettings {
    protocol Category: Codable, Sendable {
        
    }
    
    func save() throws {
        
    }
    
    func load() throws {
        
    }
}
