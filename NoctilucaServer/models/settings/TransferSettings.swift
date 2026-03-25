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

        /// 최대 업로드 속도 (KB/s 단위, 0 = 무제한)
        var maxUploadSpeedKBps: Int = 0

        init() {}

        enum CodingKeys: String, CodingKey {
            case integrityCheckMethod
            case enableCompression
            case maxUploadSpeedKBps
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableCompression = container.decodeSafe(Bool.self, forKey: .enableCompression, default: enableCompression)
            maxUploadSpeedKBps = container.decodeSafe(Int.self, forKey: .maxUploadSpeedKBps, default: maxUploadSpeedKBps)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(enableCompression, forKey: .enableCompression)
            try container.encode(maxUploadSpeedKBps, forKey: .maxUploadSpeedKBps)
        }
    }
}
