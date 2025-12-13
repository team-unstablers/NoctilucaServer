//
//  NoctilucaClientSession+Auth.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

extension NoctilucaClientSession {
    /// ServerHello 메시지를 생성한다.
    func serverHelloMessage() -> ServerHello {
        let transportSettings = server.settings.transport
        
        let serverName = server.serverName(withVersion: transportSettings.disableServerVersionAnnouncement)
        let motd = transportSettings.motd
        
        let supportedFeatures: [UUID] = if !transportSettings.disableSupportedFeaturesAnnouncement {
            server.featureProvider.supportedFeatures().map { $0.rawValue }
        } else {
            []
        }
        
        let serverHello = ServerHello(
            protocolVersion: .v1_0,
            supportedFeatures: supportedFeatures,
            serverName: serverName,
            motd: motd
        )
        
        return consume serverHello
    }
    
    /// 32bytes 정도의 랜덤한 nonce를 생성한다.
    func generateNonce() -> Data {
        var nonce = Data(count: 32)
        let result = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        
        precondition(result == errSecSuccess, "Failed to generate random nonce")
        return nonce
    }
    
    /// 인증 챌린지 메시지를 생성한다.
    func authChallengeMessage(nonce: Data) -> AuthChallenge {
        let acceptedMethods = server.authenticator.supportedMethods().map {
            $0.rawValue
        }
        let message = server.settings.transport.authChallengeMessage
        
        let challenge = AuthChallenge(
            acceptedMethods: consume acceptedMethods,
            nonce: nonce,
            message: message
        )
        
        return consume challenge
    }
    
    func handleClientHello(_ message: ClientHello) async throws {
        try self.assertPhase(expected: .initial)
        logger.debug("Received ClientHello from agent: \(message.agentName), protocol version: \(message.protocolVersion)")
        
        // negotiate protocol version, features, etc.
        guard message.protocolVersion == .v1_0 else {
            throw NoctilucaClientSessionError.unsupportedProtocolVersion
        }
        
        // OK, 우선 ClientInfo를 심는다
        self.clientInfo = ClientInfo(
            agentName: message.agentName,
            protocolVersion: message.protocolVersion
        )
        
        try self.shiftPhase(to: .awaitingAuthentication)
       
        // respond with ServerHello
        try await self.mainChannel.sendServerHello(serverHelloMessage())
        
        let nonce = self.generateNonce()
        self.authNonce = nonce
        try await self.mainChannel.sendAuthChallenge(authChallengeMessage(nonce: nonce))
        
        // 60초 이내에 AuthRequest를 받아서 처리해야 한다
        // TODO: 이 값은 설정 가능하도록 한다
        self.startPhaseShiftAssertion(expect: .ready, within: 60)
    }
    
    func handleAuthRequest(_ message: consuming AuthRequest) async throws {
        /// 인증 실패 처리.
        /// nonce를 재설정하고, 새로운 AuthChallenge를 보낸다.
        func __failure() async throws {
            // 무차별 대입 공격을 방지하기 위해 약간의 지연을 둔다
            // 3초, 6초, 9초, ...
            let seconds = max(3 * UInt64(self.loginAttempts + 1), 10)
            try? await Task.sleep(for: .seconds(seconds))
            
            self.loginAttempts += 1
            
            guard self.loginAttempts < server.settings.security.maxLoginAttempts else {
                logger.warning("Maximum login attempts exceeded for session \(self.id). Closing connection.")
                
                await self.close()
                return
            }
            
            let nonce = self.generateNonce()
            self.authNonce = nonce
            try await self.mainChannel.sendAuthChallenge(authChallengeMessage(nonce: nonce))
            
            // 60초 이내에 AuthRequest를 받아서 처리해야 한다
            // TODO: 이 값은 설정 가능하도록 한다
            self.startPhaseShiftAssertion(expect: .ready, within: 60)
        }
        
        try self.assertPhase(expected: .awaitingAuthentication)
        logger.debug("Received AuthRequest with method: \(message.method)")
        
        let method = AuthMethod(rawValue: message.method)
        guard server.authenticator.supports(method: method) else {
            // unsupported method는 뱉어낸다.
            try? await self.notice(.error, code: .unsupportedAuthMethod)
            try await __failure()
            return
        }
        
        guard let authNonce = self.authNonce,
              message.nonce == authNonce
        else {
            // nonce가 일치하지 않는 경우 실패 처리한다
            try? await self.notice(.error, code: .nonceDismatch)
            try await __failure()
            return
        }
        
        let result = await server.authenticator.authenticate(using: method, payload: message.payload)
        
        switch result {
        case .success(let uid):
            // 인증에 성공했으므로 추가 채널을 만들 수 있도록 허용한다
            session.shouldAcceptChannelCreation = true
            try self.shiftPhase(to: .ready)
            
            try await self.mainChannel.sendAuthResponse(AuthResponse(sessionID: self.id))
            return
            
        case .failure(let error):
            logger.error("Authentication failed: \(error.localizedDescription)")
            try await __failure()
            
            return
        }
    }
    
}

