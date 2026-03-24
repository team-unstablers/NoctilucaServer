//
//  TransferSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//

import Foundation

extension AppSettings {
    struct Transfer: Category {
        /// Zstd 압축 사용 여부
        var enableCompression: Bool = true

        init() {}

        enum CodingKeys: String, CodingKey {
            case integrityCheckMethod
            case enableCompression
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableCompression = container.decodeSafe(Bool.self, forKey: .enableCompression, default: enableCompression)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(enableCompression, forKey: .enableCompression)
        }
    }
}
