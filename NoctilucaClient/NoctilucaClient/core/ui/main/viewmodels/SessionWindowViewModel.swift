//
//  SessionWindowViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//
import Foundation

import AVFoundation

import SwiftUI
import Combine

import SiriusKitClient

@MainActor
class SessionWindowViewModel: ObservableObject {
    @Published
    var phase: MainWindowPhase = .newConnection

    @Published
    var endpointURL: String = ""

    @Published
    var errors: [NoctilucaClientError] = []

    @Published
    var shouldDisplayErrorAlert: Bool = false

    @Published
    var inputWarning: InputWarning? = nil

    @Published
    private(set) var sessionSettings: SessionSettings? = nil

    @Published
    private(set) var isInputLockActive: Bool = false

    @Published
    var contactSheetCoordinator: ContactSheetCoordinator

    @Published
    var shouldPresentDisplaySwitchSheet: Bool = false
    

    private var settingsStore: SettingsStore?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var sessionCancellables: Set<AnyCancellable> = []

    @Published
    private(set) var remoteSession: RemoteSession? = nil

    private var client: NoctilucaClient? {
        remoteSession?.client
    }

    init() {
        self.contactSheetCoordinator = ContactSheetCoordinator()
        setupContactSheetCoordinator()
    }

    private func setupContactSheetCoordinator() {
        contactSheetCoordinator.onConnect = { [weak self] endpoint, settingsOverride in
            Task { @MainActor in
                try? await self?.startSession(endpoint: endpoint, settingsOverride: settingsOverride)
            }
        }
    }

    func startSession(endpoint: EndpointKind, settingsOverride: SessionSettings? = nil) async throws {
        if remoteSession != nil {
            await stopSession()
        }

        // FIXME: IPv6 지원하지 않는다
        let endpointURL = endpoint.endpointURL
        let host = endpointURL.split(separator: ":").first
        let port = UInt16(endpointURL.split(separator: ":").last ?? "") ?? 8282

        guard let host else {
            return
        }

        self.endpointURL = endpointURL
        self.phase = .connecting

        if let settingsOverride {
            self.sessionSettings = settingsOverride
        } else {
            switch endpoint {
            case .contact(let item):
                self.sessionSettings = item.settings
            case .quickConnect:
                self.sessionSettings = settingsStore?.settings.sessionDefaults ?? SessionSettings(scope: .global)
            case .connect:
                assertionFailure("connect endpoint should be handled by UI")
                self.sessionSettings = settingsStore?.settings.sessionDefaults ?? SessionSettings(scope: .global)
            }
        }

        let clientManager = NoctilucaClientManager.shared
        let client = try await clientManager.createClient(to: String(host), port: port, settings: self.sessionSettings)

        if let sessionSettings = self.sessionSettings {
            configureAuthCredentials(for: client, endpoint: endpoint, sessionSettings: sessionSettings)
        }

        if let settingsStore {
            client.applyInputRedirectionMethod(settingsStore.settings.input.redirectionMethod)
            client.applyPointerInputMode(settingsStore.settings.input.pointerInputMode)
        }

        let remoteSession = RemoteSession(client)
        attachRemoteSession(remoteSession)

        do {
            try await remoteSession.setup()
            try await remoteSession.startup()
        } catch {
            phase = .newConnection
            detachRemoteSession()
            await clientManager.killClient(id: client.id)
            throw error
        }
    }

    func stopSession() async {
        guard let remoteSession else {
            return
        }

        let client = remoteSession.client
        detachRemoteSession()

        await NoctilucaClientManager.shared.killClient(id: client.id)

        endpointURL = ""
        sessionSettings = nil
        inputWarning = nil

        phase = .newConnection
    }

    func bind(settingsStore: SettingsStore) {
        if self.settingsStore === settingsStore {
            return
        }

        self.settingsStore = settingsStore
        contactSheetCoordinator.settingsStore = settingsStore
        settingsCancellables.forEach { $0.cancel() }
        settingsCancellables.removeAll()

        settingsStore.$settings
            .map { $0!.input.redirectionMethod }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] method in
                self?.applyInputRedirectionMethod(method)
            }
            .store(in: &settingsCancellables)

        settingsStore.$settings
            .map { $0!.input.pointerInputMode }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.applyPointerInputMode(mode)
            }
            .store(in: &settingsCancellables)
    }

    func loadContacts() {
        ContactsStore.shared.loadContacts()
    }

    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction) async {
        await remoteSession?.handleAuthChallengeResponse(action)
    }

    func handleClientPhaseChanged(_ phase: NoctilucaClientPhase) {
        switch phase {
        case .initial:
            self.phase = .connecting
        case .awaitingAuthentication:
            break
        case .ready:
            self.phase = .connected
        case .panic:
            break
        case .closed:
            Task { @MainActor in
                await self.stopSession()
            }
        }
    }

    func handleClientError(_ error: NoctilucaClientError) {
        errors.append(error)
        shouldDisplayErrorAlert = true
    }

    private func configureAuthCredentials(
        for client: NoctilucaClient,
        endpoint: EndpointKind,
        sessionSettings: SessionSettings
    ) {
        let sessionEntries = loadSessionCredentials(for: endpoint, sessionSettings: sessionSettings)
        let globalEntries = loadGlobalCredentials()

        client.configureAuthCredentials(sessionEntries: sessionEntries, globalEntries: globalEntries)
    }

    private func loadSessionCredentials(for endpoint: EndpointKind, sessionSettings: SessionSettings) -> [ClientAuthEntry] {
        guard sessionSettings.scope == .session else {
            return []
        }

        let contactId: UUID?
        switch endpoint {
        case .contact(let item):
            contactId = item.id
        default:
            contactId = nil
        }

        return SessionCredentialsStore.load(
            scope: .session,
            contactId: contactId,
            keyOverride: sessionSettings.credentials.keychainKey
        )
    }

    private func loadGlobalCredentials() -> [ClientAuthEntry] {
        guard let settingsStore else {
            return []
        }

        let globalSettings = settingsStore.settings.sessionDefaults
        return SessionCredentialsStore.load(
            scope: .global,
            contactId: nil,
            keyOverride: globalSettings.credentials.keychainKey
        )
    }

    func handleInputWarningUpdated(_ warning: InputWarning?) {
        inputWarning = warning
    }

    func retryInputRedirection() {
        guard let settingsStore else {
            return
        }

        applyInputRedirectionMethod(settingsStore.settings.input.redirectionMethod)
    }

    private func applyInputRedirectionMethod(_ method: AppSettings.InputRedirectionMethod) {
        guard let client else {
            return
        }

        client.applyInputRedirectionMethod(method)
    }

    private func applyPointerInputMode(_ mode: AppSettings.PointerInputMode) {
        guard let client else {
            return
        }

        client.applyPointerInputMode(mode)
    }

    func dismissLastError() {
        if !errors.isEmpty {
            errors.removeLast()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldDisplayErrorAlert = !self.errors.isEmpty
        }
    }

    private func attachRemoteSession(_ session: RemoteSession) {
        remoteSession = session

        sessionCancellables.forEach { $0.cancel() }
        sessionCancellables.removeAll()

        session.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handleClientPhaseChanged(phase)
            }
            .store(in: &sessionCancellables)

        session.errorPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                self?.handleClientError(error)
            }
            .store(in: &sessionCancellables)
    }

    private func detachRemoteSession() {
        sessionCancellables.forEach { $0.cancel() }
        sessionCancellables.removeAll()
        remoteSession = nil
    }
}
