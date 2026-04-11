//
//  RecentConnectionStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation
import Combine

@MainActor
final class RecentConnectionStore: ObservableObject {
    static let shared = RecentConnectionStore()

    private static let fileName = "recent-connections.json"
    private static let maxRecords = 10

    @Published private(set) var records: [RecentConnectionRecord] = []

    private init() {
        load()
    }

    // MARK: - Public API

    func add(
        endpointURL: String,
        displayName: String,
        icon: SessionSettings.ContactIcon,
        contactId: UUID?
    ) {
        if let index = records.firstIndex(where: { $0.endpointURL == endpointURL }) {
            records[index].timestamp = Date()
            records[index].displayName = displayName
            records[index].iconSymbol = icon.symbol.rawValue
            records[index].iconBackground = icon.background.rawValue
            records[index].contactId = contactId
        } else {
            let record = RecentConnectionRecord(
                id: UUID(),
                endpointURL: endpointURL,
                displayName: displayName,
                timestamp: Date(),
                iconSymbol: icon.symbol.rawValue,
                iconBackground: icon.background.rawValue,
                contactId: contactId
            )
            records.insert(record, at: 0)
        }

        records.sort { $0.timestamp > $1.timestamp }

        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }

        save()
    }

    // MARK: - Persistence

    func load() {
        do {
            let url = try fileURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                records = []
                return
            }
            let data = try Data(contentsOf: url)
            records = try Self.jsonDecoder.decode([RecentConnectionRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func save() {
        do {
            let url = try fileURL()
            let directory = url.deletingLastPathComponent()

            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            let data = try Self.jsonEncoder.encode(records)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // save 실패는 무시 (다음 앱 시작 시 재시도)
        }
    }

    private func fileURL() throws -> URL {
        let base = try AppSettings.applicationSupportDirectory()
        return base.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    // MARK: - JSON Encoder/Decoder

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
