//
//  ContactsStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Combine

enum ContactsStoreError: LocalizedError {
    case contactNotFound
}

final class ContactsStore: ObservableObject {
    static let shared = ContactsStore()

    private static let contactsDirectoryName = "contacts"

    @Published private(set) var contacts: [ContactItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    private init() {
        loadContacts()
    }

    // MARK: - Public API

    func loadContacts() {
        isLoading = true
        loadError = nil
        do {
            let loaded = try loadAll()
            contacts = loaded.sorted { $0.displayName < $1.displayName }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func save(_ contact: ContactItem) throws {
        let fileManager = FileManager.default
        let url = try contactURL(for: contact.id)

        if !fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let json = try Self.jsonEncoder.encode(contact)
        try json.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        loadContacts()
    }

    func remove(id: UUID) throws {
        let fileManager = FileManager.default
        let url = try contactURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let credentialsRef = contacts.first(where: { $0.id == id })?.settings.credentials
            ?? SessionSettings.CredentialsRef()
        _ = SessionCredentialsStore.remove(
            scope: .session,
            contactId: id,
            currentRef: credentialsRef
        )

        try fileManager.removeItem(at: url)
        loadContacts()
    }

    // MARK: - Private

    private func loadAll() throws -> [ContactItem] {
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
            guard var contact = try? Self.jsonDecoder.decode(ContactItem.self, from: Data(contentsOf: url)) else {
                return nil
            }
            contact.normalizeAfterLoad()
            return contact
        }
    }

    private func contactURL(for id: UUID) throws -> URL {
        try contactsDirectory().appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func contactsDirectory() throws -> URL {
        let base = try AppSettings.applicationSupportDirectory()
        return base.appendingPathComponent(Self.contactsDirectoryName, isDirectory: true)
    }

    // MARK: - JSON Encoder/Decoder

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}
