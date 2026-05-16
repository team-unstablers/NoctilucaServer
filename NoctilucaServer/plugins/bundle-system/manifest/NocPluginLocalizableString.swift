//
//  NocPluginLocalizableString.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation

struct NocPluginLocalizableString: Codable, Equatable, Hashable {
    static let defaultKey = "default"

    let strings: [String: String]

    init(strings: [String: String]) {
        self.strings = strings
    }

    init(_ string: String) {
        self.strings = [Self.defaultKey: string]
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self.strings = [Self.defaultKey: string]
            return
        }

        let dict = try container.decode([String: String].self)
        guard dict[Self.defaultKey] != nil else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "NocPluginLocalizableString object form must contain '\(Self.defaultKey)' key"
            )
        }
        self.strings = dict
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        if strings.count == 1, let onlyDefault = strings[Self.defaultKey] {
            try container.encode(onlyDefault)
            return
        }

        try container.encode(strings)
    }

    func getString(for locale: Locale = .current) -> String {
        if let value = strings[locale.identifier] {
            return value
        }

        if let languageCode = locale.language.languageCode?.identifier,
           let value = strings[languageCode] {
            return value
        }

        return strings[Self.defaultKey] ?? ""
    }
}
