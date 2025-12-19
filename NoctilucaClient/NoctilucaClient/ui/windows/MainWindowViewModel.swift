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
    
    var __tmp_keyboard: HIDIOGCKeyboard?
    
    func testKeyboard() {
    }

    func appendConnectionLog(_ log: String) {
        self.connectionLog.append(log)
        
        // 마지막 6개 정도만 남긴다
        if self.connectionLog.count > 6 {
            self.connectionLog.removeFirst(self.connectionLog.count - 6)
        }
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
        
        self.client = client
        
        try await client.setup()
        self.appendConnectionLog("Sirius 프로토콜 클라이언트를 초기화했습니다")
        
        try await client.startup()
        self.appendConnectionLog("연결을 시작합니다")
    }
    
    func stopSession() async throws {
        guard let client = self.client else {
            return
        }
        
        await client.close()
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
        }
    }
    
    func handleClientError(_ error: NoctilucaClientError) {
        self.errors.append(error)
        self.shouldDisplayErrorAlert = true
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
