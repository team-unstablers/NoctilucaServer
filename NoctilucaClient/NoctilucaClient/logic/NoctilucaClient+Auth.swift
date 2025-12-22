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

        let acceptedMethods = message.acceptedMethods.map { ClientAuthMethod(rawValue: $0) }
        let availableMethods = authenticator.availableMethods(for: message)
        if availableMethods.isEmpty {
            logger.error("No supported auth methods for challenge: \(message.acceptedMethods)")
            await MainActor.run {
                uiEvents.send(.errorOccurred(.authNegotiationFailed(authMethods: acceptedMethods)))
            }
            
            // Close the connection gracefully
            await self.close()
            return
        }

        if let autoRequest = authenticator.nextAutoAuthRequest(for: message) {
            logger.info("Attempting auto authentication using method: \(autoRequest.method.rawValue)")
            try await sendAuthRequest(autoRequest.method.rawValue, nonce: message.nonce, payload: autoRequest.payload)
            return
        }

        await MainActor.run {
            uiEvents.send(.receivedAuthChallenge(message))
        }
    }
    
    func handleAuthResponse(_ message: consuming AuthResponse) async throws {
        try assertPhase(expected: .awaitingAuthentication)
        logger.info("Received AuthResponse: sessionId=\(message.sessionID!.uuidString))")
        
        self.sessionID = message.sessionID
        try shiftPhase(to: .ready)
        
        try await self.startSession()
    }
}
