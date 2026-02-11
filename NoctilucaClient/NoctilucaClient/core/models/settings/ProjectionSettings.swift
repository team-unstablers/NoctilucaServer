//
//  GeneralSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct Projection: Category {
        var enableJitterBuffer: Bool = true
        
        init() {}

        enum CodingKeys: String, CodingKey {
            case enableJitterBuffer
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableJitterBuffer = container.decodeSafe(Bool.self, forKey: .enableJitterBuffer, default: true)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enableJitterBuffer, forKey: .enableJitterBuffer)
        }
    }
}
