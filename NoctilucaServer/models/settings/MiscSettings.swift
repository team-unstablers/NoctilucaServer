//
//  MiscSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct Telemetry: Category {
        var enableTelemetry: Bool = false
        var telemetryIdentifier: UUID? = nil
    }
}
