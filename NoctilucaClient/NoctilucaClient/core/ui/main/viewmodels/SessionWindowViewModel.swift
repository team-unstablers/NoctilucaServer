//
//  SessionWindowViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//
import Foundation

import AVFoundation
import Security

import SwiftUI
import Combine

import SiriusKitClient

@MainActor
class SessionWindowViewModel: ObservableObject {
#if os(iOS)
    var rootViewController: Weak<RootViewController>? = nil
#endif
    
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

    /// macOS에서 디스플레이를 별도 창으로 분리하는 콜백.
    /// AppKitMainWindowController가 SubDisplayWindowManager를 통해 주입한다.
    var onDetachDisplay: ((Int) async throws -> Void)?

#if os(iOS)
    @Published
    var isFullscreen: Bool = false

    @Published
    var isFullscreenOverlayVisible: Bool = false

    private var autoHideTask: Task<Void, Never>?
#endif
    
    private var currentEndpoint: EndpointKind?

    private var settingsStore: SettingsStore?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var sessionCancellables: Set<AnyCancellable> = []

    @Published
    private(set) var degradationNotice: DegradationNotice? = nil

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
                do {
                    try await self?.startSession(endpoint: endpoint, settingsOverride: settingsOverride)
                } catch {
                    self?.presentConnectionError(error)
                }
            }
        }
    }

    func startSession(
        endpoint: EndpointKind,
        settingsOverride: SessionSettings? = nil,
        succeedValidationDecision: SucceedValidationDecision? = nil
    ) async throws {
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
        self.currentEndpoint = endpoint
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
        let client = try await clientManager.createClient(
            to: String(host),
            port: port,
            settings: self.sessionSettings,
        )
        
        client.succeedValidationDecision = succeedValidationDecision

        if let sessionSettings = self.sessionSettings {
            configureAuthCredentials(for: client, endpoint: endpoint, sessionSettings: sessionSettings)
        }

        let remoteSession = RemoteSession(client)
        attachRemoteSession(remoteSession)

        do {
            try await remoteSession.setup()
            try await remoteSession.startup()
        } catch {
            // 인증서 검증 대기 상태인 경우 세션을 정리하지 않고 검증 시트를 표시
            if client.isValidatingServerIdentity {
                return
            }
            
            /*
            if let pending = client.pendingIdentityValidation {
                remoteSession.presentIdentityValidation(
                    identity: pending.identity,
                    extraInfo: pending.extraInfo
                )
                return
            }
             */

            phase = .newConnection
            detachRemoteSession()
            await clientManager.killClient(id: client.id)
            throw error
        }
    }

    func stopSession(force: Bool = false) async {
        guard let remoteSession else {
            return
        }

        let client = remoteSession.client

        if !force && client.isValidatingServerIdentity {
            return
        }

        detachRemoteSession()

        if force {
            await NoctilucaClientManager.shared.killClient(id: client.id)
        } else {
            await client.closeWithGoodbye()
        }

        endpointURL = ""
        currentEndpoint = nil
        sessionSettings = nil
        inputWarning = nil
        onDetachDisplay = nil

#if os(iOS)
        isFullscreen = false
        hideFullscreenOverlay()
#endif
        

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
    }

    func loadContacts() {
        ContactsStore.shared.loadContacts()
    }

    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction) async {
        await remoteSession?.handleAuthChallengeResponse(action)
    }
    
    func performReconnect(decision: SucceedValidationDecision) async throws {
        remoteSession?.shouldPresentIdentityValidationSheet = false
        
        await self.cleanupForReconnect()
        try await self.startSession(
            endpoint: .quickConnect(endpointURL: self.endpointURL),
            settingsOverride: self.sessionSettings,
            succeedValidationDecision: decision
        )
    }

    private func cleanupForReconnect() async {
        guard let remoteSession else { return }
        let client = remoteSession.client
        detachRemoteSession()
        await NoctilucaClientManager.shared.killClient(id: client.id)
        // phase는 변경하지 않음 (.connecting 유지)
    }

    func handleClientPhaseChanged(_ phase: NoctilucaClientPhase) {
        switch phase {
        case .initial:
            self.phase = .connecting
        case .awaitingAuthentication:
            break
        case .ready:
            self.phase = .connected
            recordRecentConnection()
        case .panic:
            break
        case .closed:
            Task { @MainActor in
                await self.stopSession()
            }
        }
    }

    func presentConnectionError(_ error: Error) {
        if let clientError = error as? NoctilucaClientError {
            errors.append(clientError)
        } else {
            errors.append(.connectionFailed(error))
        }
        shouldDisplayErrorAlert = true
    }

    /// Contact sheet dismiss 완료 후 호출되어, sheet 전환 중 누락된 에러 alert를 표시한다.
    func flushPendingConnectionErrors() {
        guard !errors.isEmpty else { return }
        shouldDisplayErrorAlert = true
    }

    func handleClientError(_ error: NoctilucaClientError) {
        guard (client?.isValidatingServerIdentity ?? false) == false else {
            // 인증서 검증 시에 발생하는 접속 끊김은 어쩔 수 없는 것
            return
        }
        
        errors.append(error)
        shouldDisplayErrorAlert = true
    }

    private func recordRecentConnection() {
        guard let endpoint = currentEndpoint else { return }
        let icon = sessionSettings?.general?.icon ?? SessionSettings.ContactIcon()

        let displayName: String
        let contactId: UUID?

        switch endpoint {
        case .contact(let item):
            displayName = item.displayName
            contactId = item.id
            var updated = item
            updated.lastConnectedAt = Date()
            try? ContactsStore.shared.save(updated)
        case .quickConnect(let url):
            displayName = url
            contactId = nil
        case .connect(let url):
            displayName = url
            contactId = nil
        }

        RecentConnectionStore.shared.add(
            endpointURL: endpointURL,
            displayName: displayName,
            icon: icon,
            contactId: contactId
        )
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
        session.parent = Weak(self)

        sessionCancellables.forEach { $0.cancel() }
        sessionCancellables.removeAll()

        session.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handleClientPhaseChanged(phase)
            }
            .store(in: &sessionCancellables)

        session.errorPublisher
            .sink { [weak self] error in
                self?.handleClientError(error)
            }
            .store(in: &sessionCancellables)

        session.$projection
            .compactMap { $0 }
            .flatMap { $0.$degradationNotice }
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in
                self?.degradationNotice = notice
            }
            .store(in: &sessionCancellables)
    }

    private func detachRemoteSession() {
        sessionCancellables.forEach { $0.cancel() }
        sessionCancellables.removeAll()
        remoteSession = nil
        degradationNotice = nil
    }

    // MARK: - Fullscreen (iOS)
#if os(iOS)
    func showFullscreenOverlay() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isFullscreenOverlayVisible = true
        }
        scheduleAutoHideOverlay()
    }

    func hideFullscreenOverlay() {
        autoHideTask?.cancel()
        autoHideTask = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            isFullscreenOverlayVisible = false
        }
    }

    func scheduleAutoHideOverlay() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                isFullscreenOverlayVisible = false
            }
        }
    }
#endif
}
