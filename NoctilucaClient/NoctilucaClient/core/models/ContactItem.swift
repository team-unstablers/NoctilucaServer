//
//  ContactItem.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import Foundation
import SiriusKitClient

struct ContactItem: Codable, Identifiable, Sendable {
    static let currentSchemaVersion: Int = 2

    var schemaVersion: Int = Self.currentSchemaVersion
    var id: UUID
    var settings: SessionSettings
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String?,
        endpointURL: String,
        preset: SessionSettings? = nil
    ) {
        self.id = id

        var baseSettings = preset ?? SessionSettings(scope: .session)
        baseSettings.scope = .session

        var general = baseSettings.general ?? SessionSettings.General()
        general.displayName = name ?? ""
        general.endpoint = SREndpoint.parse(endpointURL)
        baseSettings.general = general
        baseSettings.credentials.keychainKey = SessionSettings.credentialsKey(for: .session, contactId: id)

        self.settings = baseSettings
    }
}

extension ContactItem {
    mutating func normalizeAfterLoad() {
        settings.scope = .session
        if settings.general == nil {
            settings.general = SessionSettings.General()
        }
        settings.ensureCredentialsKey(scope: .session, contactId: id)
    }

    var displayName: String {
        let name = settings.general?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            return name
        }

        let url = endpointURL
        return url.isEmpty ? "Unknown" : url
    }

    var endpointURL: String {
        guard let endpoint = settings.general?.endpoint else { return "" }
        if case .hostname(let name) = endpoint.address, name.isEmpty { return "" }
        return endpoint.description
    }
}
