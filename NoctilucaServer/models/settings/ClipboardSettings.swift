//
//  ClipboardSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//

import Foundation

enum ClipboardSyncDirection: String, Codable, Sendable {
    case localToRemote = "local-to-remote"
    case remoteToLocal = "remote-to-local"
    case bidirectional = "bidirectional"
}

extension AppSettings {
    struct Clipboard: Category {
        /// 클립보드 공유 기능 활성화 여부
        var enabled: Bool = true

        /// 클립보드 공유 방향
        var syncDirection: ClipboardSyncDirection = .bidirectional

        /// 텍스트 데이터만 허용할지 여부.
        /// 활성화 시 이미지, 리치 텍스트, 알려지지 않은 형식, 파일 공유가 무시됩니다.
        var textOnly: Bool = false

        /// 이미지 데이터 공유 허용 여부
        var allowImage: Bool = true

        /// 리치 텍스트 / HTML 데이터 공유 허용 여부
        var allowRichText: Bool = true

        /// 알려지지 않은 형식의 데이터 공유 허용 여부
        var allowUnknownFormat: Bool = true

        /// 파일 복사 허용 여부
        var allowFile: Bool = true

        init() {}

        enum CodingKeys: String, CodingKey {
            case enabled
            case syncDirection
            case textOnly
            case allowImage
            case allowRichText
            case allowUnknownFormat
            case allowFile
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enabled = container.decodeSafe(Bool.self, forKey: .enabled, default: enabled)
            syncDirection = container.decodeSafe(ClipboardSyncDirection.self, forKey: .syncDirection, default: syncDirection)
            textOnly = container.decodeSafe(Bool.self, forKey: .textOnly, default: textOnly)
            allowImage = container.decodeSafe(Bool.self, forKey: .allowImage, default: allowImage)
            allowRichText = container.decodeSafe(Bool.self, forKey: .allowRichText, default: allowRichText)
            allowUnknownFormat = container.decodeSafe(Bool.self, forKey: .allowUnknownFormat, default: allowUnknownFormat)
            allowFile = container.decodeSafe(Bool.self, forKey: .allowFile, default: allowFile)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(enabled, forKey: .enabled)
            try container.encode(syncDirection, forKey: .syncDirection)
            try container.encode(textOnly, forKey: .textOnly)
            try container.encode(allowImage, forKey: .allowImage)
            try container.encode(allowRichText, forKey: .allowRichText)
            try container.encode(allowUnknownFormat, forKey: .allowUnknownFormat)
            try container.encode(allowFile, forKey: .allowFile)
        }
    }
}
