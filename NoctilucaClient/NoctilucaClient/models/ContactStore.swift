//
//  ContactStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Combine

enum ContactStoreError: LocalizedError {
    case contactNotFound
}

final class ContactStore: ObservableObject {
    private static let contactsDirectoryName = "contacts"
    static let shared = ContactStore()
    static let didChangeNotification = Notification.Name("NoctilucaClient.ContactStoreDidChange")

    @Published
    private(set) var contacts: [ContactItem] = []

    @Published
    private(set) var isLoadingContacts: Bool = false

    @Published
    private(set) var contactsLoadError: String? = nil

    private var contactsCancellable: AnyCancellable?

    private init(loadFromDisk: Bool = true) {
        if loadFromDisk {
            loadContacts()
        }
    }

    func startContactObservation() {
        guard contactsCancellable == nil else {
            return
        }

        loadContacts()

        contactsCancellable = NotificationCenter.default
            .publisher(for: Self.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if let sender = notification.object as? ContactStore, sender === self {
                    return
                }
                self.loadContacts()
            }
    }

    func save(_ contact: ContactItem) throws {
        try Self.saveToDisk(contact)
        upsert(contact)
        contactsLoadError = nil
        notifyChange()
    }

    func load(id: UUID) throws -> ContactItem {
        try Self.loadFromDisk(id: id)
    }

    func reload() {
        loadContacts()
    }

    func remove(id: UUID) throws {
        try Self.removeFromDisk(id: id)
        contacts.removeAll { $0.id == id }
        contacts = contacts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        contactsLoadError = nil
        notifyChange()
    }

    private func loadContacts() {
        isLoadingContacts = true
        contactsLoadError = nil
        defer { isLoadingContacts = false }

        do {
            let loaded = try Self.loadAllFromDisk()
            contacts = loaded.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            contacts = []
            contactsLoadError = error.localizedDescription
        }
    }

    private func upsert(_ contact: ContactItem) {
        var normalized = contact
        normalized.normalizeAfterLoad()

        var nextContacts = contacts.filter { $0.id != contact.id }
        nextContacts.append(normalized)
        nextContacts.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        contacts = nextContacts
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

private extension ContactStore {
    static func saveToDisk(_ contact: ContactItem) throws {
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

    static func loadFromDisk(id: UUID) throws -> ContactItem {
        let fileManager = FileManager.default
        let url = try contactURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ContactStoreError.contactNotFound
        }

        var contact = try jsonDecoder.decode(ContactItem.self, from: Data(contentsOf: url))
        contact.normalizeAfterLoad()
        return contact
    }

    static func loadAllFromDisk() throws -> [ContactItem] {
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

    static func removeFromDisk(id: UUID) throws {
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
