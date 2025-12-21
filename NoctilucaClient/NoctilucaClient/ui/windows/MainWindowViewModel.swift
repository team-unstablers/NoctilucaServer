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
    var connectionLog: [String] = []
    
    @Published
    var errors: [NoctilucaClientError] = []
    
    @Published
    var shouldDisplayErrorAlert: Bool = false
    
    var client: NoctilucaClient?
    
    @Published
    var averagePingRTT: TimeInterval = 0.0
    
    @Published
    var displayLayer: AVSampleBufferDisplayLayer? = nil

    @Published
    var inputWarning: InputWarning? = nil

    @Published
    private(set) var sessionSettings: SessionSettings? = nil

    @Published
    var contacts: [ContactItem] = []

    @Published
    var isLoadingContacts: Bool = false

    @Published
    var contactsLoadError: String? = nil

    private var settingsStore: SettingsStore?
    private var settingsCancellable: AnyCancellable?
    private var contactsCancellable: AnyCancellable?
    

    func appendConnectionLog(_ log: String) {
        self.connectionLog.append(log)
        
        // 마지막 6개 정도만 남긴다
        if self.connectionLog.count > 6 {
            self.connectionLog.removeFirst(self.connectionLog.count - 6)
        }
    }
    
    func startSession(endpoint: EndpointKind, settingsOverride: SessionSettings? = nil) async throws {
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
        
        self.appendConnectionLog("\(host):\(port) 에 연결을 시도합니다")
        
        let result = SiriusClientBuilder()
            .useTransportProtocol(.quic(host: String(host), port: port))
            .useFeatureProvider(NoctilucaFeatureProvider())
            .build()
        
        
        let session = try result.get()
        let client = NoctilucaClient(session)
        
        self.client = client

        if let settingsStore {
            client.applyInputRedirectionMethod(settingsStore.settings.input.redirectionMethod)
        }
        
        try await client.setup()
        self.appendConnectionLog("Sirius 프로토콜 클라이언트를 초기화했습니다")
        
        try await client.startup()
        self.appendConnectionLog("연결을 시작합니다")
    }
    
    func stopSession() {
        print("stopSession")
        Task {
            guard let client = self.client else {
                return
            }
            
            await client.close()
        }
        
        self.endpointURL = ""
        self.sessionSettings = nil
        self.inputWarning = nil
    }

    func bind(settingsStore: SettingsStore) {
        if self.settingsStore === settingsStore {
            return
        }

        self.settingsStore = settingsStore
        settingsCancellable?.cancel()

        settingsCancellable = settingsStore.$settings
            .map { $0!.input.redirectionMethod }
            .removeDuplicates()
            .sink { [weak self] method in
                self?.applyInputRedirectionMethod(method)
            }
    }

    func startContactObservation() {
        guard contactsCancellable == nil else {
            return
        }

        loadContacts()

        contactsCancellable = NotificationCenter.default
            .publisher(for: ContactStore.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadContacts()
            }
    }

    func loadContacts() {
        isLoadingContacts = true
        contactsLoadError = nil
        defer { isLoadingContacts = false }

        do {
            let loaded = try ContactStore.loadAll()
            contacts = loaded.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            contacts = []
            contactsLoadError = error.localizedDescription
        }
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
            self.client = nil
            self.phase = .newConnection
            self.inputWarning = nil
        }
    }
    
    func handleClientError(_ error: NoctilucaClientError) {
        self.errors.append(error)
        self.shouldDisplayErrorAlert = true
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
    
    func dismissLastError() {
        if !self.errors.isEmpty {
            self.errors.removeLast()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldDisplayErrorAlert = !self.errors.isEmpty
        }
    }
}
