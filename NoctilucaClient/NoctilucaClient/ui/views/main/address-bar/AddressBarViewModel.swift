//
//  AddressBarViewModel.swift
//  NoctilucaClient
//

import SwiftUI
import Combine

/// AddressBar의 후보 목록 및 입력 상태를 관리하는 ViewModel
@MainActor
final class AddressBarViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var draftURL: String
    @Published private(set) var candidates: [EndpointKind] = []
    @Published var candidateFocusIndex: Int? = nil

    // MARK: - Dependencies

    private let contactsStore: ContactsStore
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(initialURL: String, contactsStore: ContactsStore = .shared) {
        self.draftURL = initialURL
        self.contactsStore = contactsStore

        setupBindings()
        updateCandidates(for: initialURL)
    }

    private func setupBindings() {
        // draftURL 변경 시 후보 목록 업데이트
        $draftURL
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.candidateFocusIndex = nil
                self?.updateCandidates(for: newValue)
            }
            .store(in: &cancellables)

        // ContactsStore 변경 시 후보 목록 업데이트
        contactsStore.$contacts
            .dropFirst() // 초기값 무시
            .sink { [weak self] _ in
                guard let self else { return }
                self.candidateFocusIndex = nil
                self.updateCandidates(for: self.draftURL)
            }
            .store(in: &cancellables)
    }

    // MARK: - Candidate Navigation

    enum MoveDirection {
        case up
        case down
    }

    func moveFocus(_ direction: MoveDirection) {
        guard !candidates.isEmpty else { return }

        let currentIndex = candidateFocusIndex
        let nextIndex: Int?

        switch direction {
        case .down:
            if currentIndex == nil {
                nextIndex = 0
            } else {
                nextIndex = min(currentIndex! + 1, candidates.count - 1)
            }
        case .up:
            if currentIndex == nil {
                nextIndex = candidates.count - 1
            } else {
                nextIndex = currentIndex! - 1 >= 0 ? currentIndex! - 1 : nil
            }
        }

        candidateFocusIndex = nextIndex
    }

    func selectedCandidate() -> EndpointKind? {
        guard let index = candidateFocusIndex,
              candidates.indices.contains(index) else {
            return nil
        }

        return candidates[index]
    }

    func updateHoverIndex(_ index: Int, isHovering: Bool) {
        guard isHovering else { return }
        guard candidates.indices.contains(index) else { return }

        candidateFocusIndex = index
    }

    func selectCandidate(at index: Int) -> EndpointKind? {
        guard candidates.indices.contains(index) else { return nil }

        candidateFocusIndex = index
        return candidates[index]
    }

    // MARK: - Private Methods

    private func updateCandidates(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated: [EndpointKind] = []

        if !trimmed.isEmpty {
            updated.append(.quickConnect(endpointURL: trimmed))
            updated.append(.connect(endpointURL: trimmed))
        }

        let matches = filterContacts(for: trimmed)
        updated.append(contentsOf: matches.map { .contact(item: $0) })

        candidates = updated
    }

    private func filterContacts(for query: String) -> [ContactItem] {
        let contacts = contactsStore.contacts
        guard !contacts.isEmpty else { return [] }

        if query.isEmpty {
            return contacts
        }

        return contacts.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.endpointURL.localizedCaseInsensitiveContains(query)
        }
    }
}
