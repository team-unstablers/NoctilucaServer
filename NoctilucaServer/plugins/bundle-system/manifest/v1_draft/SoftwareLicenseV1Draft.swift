//
//  SoftwareLicenseV1Draft.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation
@preconcurrency import NoctilucaPluginKit

/// `SoftwareLicense` 의 v1-draft JSON 표현.
///
/// TS 정의:
/// ```ts
/// type SoftwareLicense =
///     | { type: 'custom', name: string, url: string, isOpenSource: boolean }
///     | { type: 'proprietary', name: string, url: string }
///     | 'mit' | 'apache2_0' | 'bsd3' | 'gplv3' | 'lgplv3' | 'cc0';
/// ```
///
/// JSON 디코딩 후 `resolved` 로 `NoctilucaPluginKit.SoftwareLicense` 를 얻습니다.
/// `NoctilucaPluginKit.SoftwareLicense.dual` 은 v1-draft 스펙에 정의되지 않아 인코딩이 불가합니다.
struct SoftwareLicenseV1Draft: Codable, Sendable {
    let resolved: SoftwareLicense

    init(_ license: SoftwareLicense) {
        self.resolved = license
    }

    private enum ObjectKey: String, CodingKey {
        case type, name, url, isOpenSource
    }

    private enum ObjectType: String {
        case custom
        case proprietary
    }

    init(from decoder: any Decoder) throws {
        let singleValue = try decoder.singleValueContainer()

        if let raw = try? singleValue.decode(String.self) {
            switch raw {
            case "mit":       self.resolved = .mit
            case "apache2_0": self.resolved = .apache2_0
            case "bsd3":      self.resolved = .bsd3
            case "gplv3":     self.resolved = .gplv3
            case "lgplv3":    self.resolved = .lgplv3
            case "cc0":       self.resolved = .cc0
            default:
                throw DecodingError.dataCorruptedError(
                    in: singleValue,
                    debugDescription: "Unknown SoftwareLicense identifier '\(raw)'"
                )
            }
            return
        }

        let container = try decoder.container(keyedBy: ObjectKey.self)
        let rawType = try container.decode(String.self, forKey: .type)

        guard let objectType = ObjectType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown SoftwareLicense object type '\(rawType)'"
            )
        }

        let name = try container.decode(String.self, forKey: .name)
        let urlString = try container.decode(String.self, forKey: .url)
        let url = URL(string: urlString)

        switch objectType {
        case .custom:
            let isOpenSource = try container.decode(Bool.self, forKey: .isOpenSource)
            self.resolved = .custom(name: name, url: url, isOpenSource: isOpenSource)
        case .proprietary:
            self.resolved = .proprietary(name: name, url: url)
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch resolved {
        case .mit:
            var c = encoder.singleValueContainer()
            try c.encode("mit")
        case .apache2_0:
            var c = encoder.singleValueContainer()
            try c.encode("apache2_0")
        case .bsd3:
            var c = encoder.singleValueContainer()
            try c.encode("bsd3")
        case .gplv3:
            var c = encoder.singleValueContainer()
            try c.encode("gplv3")
        case .lgplv3:
            var c = encoder.singleValueContainer()
            try c.encode("lgplv3")
        case .cc0:
            var c = encoder.singleValueContainer()
            try c.encode("cc0")
        case .custom(let name, let url, let isOpenSource):
            var c = encoder.container(keyedBy: ObjectKey.self)
            try c.encode("custom", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(url?.absoluteString ?? "", forKey: .url)
            try c.encode(isOpenSource, forKey: .isOpenSource)
        case .proprietary(let name, let url):
            var c = encoder.container(keyedBy: ObjectKey.self)
            try c.encode("proprietary", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(url?.absoluteString ?? "", forKey: .url)
        case .dual:
            throw EncodingError.invalidValue(resolved, .init(
                codingPath: encoder.codingPath,
                debugDescription: "SoftwareLicense.dual is not representable in v1-draft manifest"
            ))
        @unknown default:
            throw EncodingError.invalidValue(resolved, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Unknown SoftwareLicense case is not representable in v1-draft manifest"
            ))
        }
    }
}
