//
//  ContactSheetCoordinator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import SwiftUI
import Combine

final class ContactSheetCoordinator: ObservableObject {
    enum Mode: Hashable {
        case quickConnect
        case contactEditor
    }

    // MARK: - Published State

    @Published var isPresented: Bool = false
    @Published var isDeleteConfirmationPresented: Bool = false
    @Published var mode: Mode = .quickConnect
    @Published var draft: ContactItem
    @Published var isEditing: Bool = false

    // MARK: - Callbacks

    var onConnect: ((EndpointKind, SessionSettings?) -> Void)?

    // MARK: - Dependencies

    weak var settingsStore: SettingsStore?

    // MARK: - Computed Properties

    var canConnect: Bool {
        !draft.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var defaultPreset: SessionSettings {
        settingsStore?.settings.sessionDefaults ?? SessionSettings(scope: .session)
    }

    // MARK: - Initialization

    init() {
        self.draft = ContactItem(
            name: nil,
            endpointURL: "",
            preset: SessionSettings(scope: .session)
        )
    }

    // MARK: - Presentation

    func presentContactEditor(for item: ContactItem?) {
        if let item {
            draft = item
            isEditing = true
        } else {
            draft = ContactItem(
                name: nil,
                endpointURL: "",
                preset: defaultPreset
            )
            isEditing = false
        }

        mode = .contactEditor
        isPresented = true
    }

    func presentQuickConnect(endpointURL: String) {
        draft = ContactItem(
            name: nil,
            endpointURL: endpointURL,
            preset: defaultPreset
        )
        isEditing = false
        mode = .quickConnect
        isPresented = true
    }

    // MARK: - Actions

    func dismiss() {
        isPresented = false
        isDeleteConfirmationPresented = false
    }

    func requestDeleteConfirmation() {
        isDeleteConfirmationPresented = true
    }

    func cancelDeleteConfirmation() {
        isDeleteConfirmationPresented = false
    }

    func save() {
        do {
            try ContactsStore.shared.save(draft)
            dismiss()
        } catch {
            print("Failed to save contact: \(error.localizedDescription)")
        }
    }

    func delete() {
        do {
            try ContactsStore.shared.remove(id: draft.id)
            dismiss()
        } catch {
            print("Failed to delete contact: \(error.localizedDescription)")
        }
    }

    func saveAndConnect() {
        do {
            try ContactsStore.shared.save(draft)
        } catch {
            print("Failed to save contact: \(error.localizedDescription)")
        }

        dismiss()
        onConnect?(.contact(item: draft), nil)
    }

    func connectWithoutSaving() {
        let endpointURL = draft.endpointURL
        guard !endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        dismiss()
        onConnect?(.quickConnect(endpointURL: endpointURL), draft.settings)
    }
}
