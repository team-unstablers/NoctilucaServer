//
//  MainWindowViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//
import Foundation

import AVFoundation

import SwiftUI
import Combine

import SiriusKitClient

class MainWindowViewModel: ObservableObject {
    @Published
    var phase: MainWindowPhase = .newConnection

    @Published
    var endpointURL: String = ""

    @Published
    var errors: [NoctilucaClientError] = []

    @Published
    var shouldDisplayErrorAlert: Bool = false

    var client: NoctilucaClient?

    var sessionEventCoordinator: SessionEventCoordinator!

    @Published
    var averagePingRTT: TimeInterval = 0.0

    @Published
    var displayLayer: AVSampleBufferDisplayLayer? = nil

    @Published
    var inputWarning: InputWarning? = nil

    @Published
    private(set) var sessionSettings: SessionSettings? = nil

    @Published
    private(set) var isInputLockActive: Bool = false

    @Published
    var contactSheetCoordinator: ContactSheetCoordinator

    private var settingsStore: SettingsStore?
    private var settingsCancellables: Set<AnyCancellable> = []

    init() {
        self.contactSheetCoordinator = ContactSheetCoordinator()
        self.sessionEventCoordinator = SessionEventCoordinator(self)
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
        if self.client != nil {
            // TODO: confirm before stopping existing session
            await self.stopSession()
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
        
        do {
            try await client.setup()
            self.sessionEventCoordinator.bind(to: client)
            
            try await client.startup()
        } catch {
            self.phase = .newConnection
            await clientManager.killClient(id: client.id)
            
            throw error
        }
        
        self.client = client
    }
    
    func stopSession() async {
        guard let client = self.client else {
            return
        }
        self.client = nil

        await NoctilucaClientManager.shared.killClient(id: client.id)
        
        self.endpointURL = ""
        self.sessionSettings = nil
        self.inputWarning = nil
        
        if let displayLayer = self.displayLayer {
            displayLayer.flushAndRemoveImage()
            self.displayLayer = nil
        }
        
        self.phase = .newConnection
    }

    func bind(settingsStore: SettingsStore) {
        if self.settingsStore === settingsStore {
            return
        }

        self.settingsStore = settingsStore
        self.contactSheetCoordinator.settingsStore = settingsStore
        settingsCancellables.forEach { $0.cancel() }
        settingsCancellables.removeAll()

        settingsStore.$settings
            .map { $0!.input.redirectionMethod }
            .removeDuplicates()
            .sink { [weak self] method in
                self?.applyInputRedirectionMethod(method)
            }
            .store(in: &settingsCancellables)

        settingsStore.$settings
            .map { $0!.input.pointerInputMode }
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.applyPointerInputMode(mode)
            }
            .store(in: &settingsCancellables)
    }

    func loadContacts() {
        ContactsStore.shared.loadContacts()
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
        self.errors.append(error)
        self.shouldDisplayErrorAlert = true
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
        self.inputWarning = warning
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
        if !self.errors.isEmpty {
            self.errors.removeLast()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldDisplayErrorAlert = !self.errors.isEmpty
        }
    }
}
