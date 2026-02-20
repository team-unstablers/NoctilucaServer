//
//  MiscSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension DaemonSettings {
    struct Telemetry: Category {
        var enableTelemetry: Bool = false
        var telemetryIdentifier: UUID? = nil

        init() {}

        enum CodingKeys: String, CodingKey {
            case enableTelemetry
            case telemetryIdentifier
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableTelemetry = container.decodeSafe(Bool.self, forKey: .enableTelemetry, default: enableTelemetry)
            telemetryIdentifier = (try? container.decodeIfPresent(UUID.self, forKey: .telemetryIdentifier)) ?? telemetryIdentifier
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enableTelemetry, forKey: .enableTelemetry)
            try container.encodeIfPresent(telemetryIdentifier, forKey: .telemetryIdentifier)
        }
    }
}
