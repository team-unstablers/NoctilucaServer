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
    
    /// 인증 챌린지 메시지를 생성한다.
    func authChallengeMessage() -> AuthChallenge {
        let acceptedMethods = server.authenticator.supportedMethods().map {
            $0.rawValue
        }
        let message = server.settings.transport.authChallengeMessage
        
        let challenge = AuthChallenge(
            acceptedMethods: consume acceptedMethods,
            message: message
        )
        
        return consume challenge
    }
    
    func handleClientHello(_ message: ClientHello) async throws {
        try self.assertPhase(expected: .ready)
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
        try await self.mainChannel.sendAuthChallenge(authChallengeMessage())
    }
    
    func handleAuthRequest(_ message: consuming AuthRequest) async throws {
        try self.assertPhase(expected: .awaitingAuthentication)
        logger.debug("Received AuthRequest with method: \(message.method)")
        
        // TODO: unsupported method는 뱉어내야 함
        let method = AuthMethod(rawValue: message.method)
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
            
            // 무차별 대입 공격을 방지하기 위해 약간의 지연을 둔다
            // 3초, 6초, 9초, ...
            try? await Task.sleep(for: .seconds(3 * UInt64(self.loginAttempts + 1)))
            
            self.loginAttempts += 1
            
            guard self.loginAttempts < server.settings.security.maxLoginAttempts else {
                logger.warning("Maximum login attempts exceeded for session \(self.id). Closing connection.")
                
                await self.close()
                return
            }
            
            try await self.mainChannel.sendAuthChallenge(authChallengeMessage())
            return
        }
    }
    
}

