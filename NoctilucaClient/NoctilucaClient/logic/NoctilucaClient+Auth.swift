//
//  NoctilucaClient+Auth.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Combine

import SiriusKitClient

extension NoctilucaClient {
    func clientHelloMessage() -> ClientHello {
        let clientHello = ClientHello(
            protocolVersion: .v1_0,
            agentName: "\(NoctilucaMeta.productName)/\(NoctilucaMeta.version)"
        )
        
        return consume clientHello
    }
    
    func sendClientHello() async throws {
        let clientHello = clientHelloMessage()
        try await mainChannel.sendClientHello(consume clientHello)
    }
    
    func sendAuthRequest(_ method: String, nonce: Data, payload: Data) async throws {
        let authRequest = AuthRequest(
            method: method,
            nonce: nonce,
            payload: payload
        )
        
        try await mainChannel.sendAuthRequest(consume authRequest)
    }
    
    func handleServerHello(_ message: consuming ServerHello) async throws {
        try assertPhase(expected: .initial)
        
        logger.info("Received ServerHello: protocolVersion=\(message.protocolVersion.rawValue), serverName=\(message.serverName ?? "nil")")
        
        // TODO: protocol version negotiation
        try shiftPhase(to: .awaitingAuthentication)
    }
    
    func handleAuthChallenge(_ message: AuthChallenge) async throws {
        try assertPhase(expected: .awaitingAuthentication)
        logger.info("Received AuthChallenge: nonce=\(message.nonce.base64EncodedString()), methods=\(message.acceptedMethods)")
        
        // TODO: accepted methods 검사
        // TODO: ssh-key같이 자동 핸들 가능한 것을 시도해 보도록
        
        // UI에게 전가
        await MainActor.run {
            uiEvents.send(.receivedAuthChallenge(message))
        }
    }
    
    func handleAuthResponse(_ message: consuming AuthResponse) async throws {
        try assertPhase(expected: .awaitingAuthentication)
        logger.info("Received AuthResponse: sessionId=\(message.sessionID!.uuidString))")
        
        self.sessionID = message.sessionID
        try shiftPhase(to: .ready)
    }
}
