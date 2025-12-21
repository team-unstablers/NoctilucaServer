//
//  ContactStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

enum ContactStoreError: LocalizedError {
    case contactNotFound
}

struct ContactStore {
    private static let contactsDirectoryName = "contacts"

    static func save(_ contact: ContactItem) throws {
        let fileManager = FileManager.default
        let url = try contactURL(for: contact.id)

        if !fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let json = try jsonEncoder.encode(contact)
        try json.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(id: UUID) throws -> ContactItem {
        let fileManager = FileManager.default
        let url = try contactURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ContactStoreError.contactNotFound
        }

        var contact = try jsonDecoder.decode(ContactItem.self, from: Data(contentsOf: url))
        contact.normalizeAfterLoad()
        return contact
    }

    static func loadAll() throws -> [ContactItem] {
        let fileManager = FileManager.default
        let directory = try contactsDirectory()
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard var contact = try? jsonDecoder.decode(ContactItem.self, from: Data(contentsOf: url)) else {
                return nil
            }
            contact.normalizeAfterLoad()
            return contact
        }
    }

    static func remove(id: UUID) throws {
        let fileManager = FileManager.default
        let url = try contactURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    static func contactURL(for id: UUID) throws -> URL {
        try contactsDirectory().appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    static func contactsDirectory() throws -> URL {
        let base = try AppSettings.applicationSupportDirectory()
        return base.appendingPathComponent(contactsDirectoryName, isDirectory: true)
    }
}

private extension ContactStore {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}
