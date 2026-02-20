//
//  LoggingSettings.swift
//  NoctilucaServer
//

import Foundation

extension DaemonSettings {
    struct Logging: Category {
        var enableFileLogging: Bool = false
        var enableLogRotation: Bool = true
        var minimumLogLevel: String = "info"
        var maxFileSize: UInt64 = 10_485_760  // 10MB
        var maxFileCount: Int = 5

        init() {}

        enum CodingKeys: String, CodingKey {
            case enableFileLogging
            case enableLogRotation
            case minimumLogLevel
            case maxFileSize
            case maxFileCount
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableFileLogging = container.decodeSafe(Bool.self, forKey: .enableFileLogging, default: enableFileLogging)
            enableLogRotation = container.decodeSafe(Bool.self, forKey: .enableLogRotation, default: enableLogRotation)
            minimumLogLevel = container.decodeSafe(String.self, forKey: .minimumLogLevel, default: minimumLogLevel)
            maxFileSize = container.decodeSafe(UInt64.self, forKey: .maxFileSize, default: maxFileSize)
            maxFileCount = container.decodeSafe(Int.self, forKey: .maxFileCount, default: maxFileCount)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enableFileLogging, forKey: .enableFileLogging)
            try container.encode(enableLogRotation, forKey: .enableLogRotation)
            try container.encode(minimumLogLevel, forKey: .minimumLogLevel)
            try container.encode(maxFileSize, forKey: .maxFileSize)
            try container.encode(maxFileCount, forKey: .maxFileCount)
        }
    }
}
