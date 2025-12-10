//
//  MainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

import SiriusKitClient

enum MainWindowPhase: Hashable {
    case newConnection
    case connecting
}

class MainWindowViewModel: ObservableObject {
    @Published
    var phase: MainWindowPhase = .newConnection
    
    @Published
    var endpointURL: String = ""
    
    @Published
    var connectionLog: [String] = []
    
    @Published
    var authChallenge: AuthChallenge?
    
    @Published
    var shouldDisplayAuthChallengeSheet: Bool = false

    var client: NoctilucaClient?
    
    func appendConnectionLog(_ log: String) {
        connectionLog.append(log)
    }
    
    func startSession(endpointURL: String) async throws {
        let host = endpointURL.split(separator: ":").first
        let port = UInt16(endpointURL.split(separator: ":").last ?? "") ?? 8282
        
        guard let host else {
            return
        }
        
        self.endpointURL = endpointURL
        self.phase = .connecting
        
        self.appendConnectionLog("\(host):\(port) 에 연결을 시도합니다")
        
        let result = SiriusClientBuilder()
            .useTransportProtocol(.quic(host: String(host), port: port))
            .useFeatureProvider(NoctilucaFeatureProvider())
            .build()
        
        
        let session = try result.get()
        let client = NoctilucaClient(session)
        
        client.loggable = self
        client.delegate = self
        
        self.client = client
        
        try await client.setup()
        self.appendConnectionLog("Sirius 프로토콜 클라이언트를 초기화했습니다")
        
        try await client.startup()
        self.appendConnectionLog("연결을 시작합니다")
    }
}

extension MainWindowViewModel: NoctilucaClientLoggable {
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.appendConnectionLog(message)
        }
    }
}

extension MainWindowViewModel: NoctilucaClientDelegate {
    func noctilucaClient(_ client: NoctilucaClient, didReceiveAuthChallenge authChallenge: AuthChallenge) {
        DispatchQueue.main.async {
            self.authChallenge = authChallenge
            self.shouldDisplayAuthChallengeSheet = true
        }
    }
}

struct MainWindow: View {
    @StateObject
    var viewModel = MainWindowViewModel()
    
    var body: some View {
        MainToolbar(addressBar: NSHostingView(rootView: AnyView(MainToolbarAddressBar(viewModel: viewModel))))
            .frame(width: 0, height: 0)

        MainWindowContentView(viewModel: viewModel)
            .frame(minWidth: 640, minHeight: 480)
            .presentedWindowStyle(.titleBar)
            .presentedWindowToolbarStyle(.unified)
            .navigationTitle(NoctilucaMeta.productName)
    }
}
