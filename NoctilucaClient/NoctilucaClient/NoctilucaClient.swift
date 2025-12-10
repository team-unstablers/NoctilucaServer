//
//  NoctilucaClient.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

import SiriusKitClient

protocol NoctilucaClientLoggable: AnyObject {
    func log(_ message: String)
}

protocol NoctilucaClientDelegate: AnyObject {
    func noctilucaClient(_ client: NoctilucaClient, didReceiveAuthChallenge authChallenge: AuthChallenge)
}

class NoctilucaClient {
    private let logger = SiriusLogger(category: "NoctilucaClient", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    let session: SiriusClient
    
    weak var delegate: NoctilucaClientDelegate?
    weak var loggable: NoctilucaClientLoggable?

    init(_ session: SiriusClient) {
        self.session = session
        
        self.session.delegate = self
    }
    
    func setup() async throws {
        try await session.setup()
    }
    
    func startup() async throws {
        logger.info("Starting up NoctilucaClient...")
        try await session.startup()
    }
}


extension NoctilucaClient: SiriusClientDelegate {
    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel) {
        self.loggable?.log("메인 채널을 생성했습니다")
        
        logger.info("Main channel created with ID: \(mainChannel.identifier)")
        
        Task {
            self.loggable?.log("Sirius 프로토콜 핸드셰이크를 시작합니다: 프로토콜 버전 \(SiriusProtocolVersion.v1_0.rawValue)를 사용합니다")
            try await mainChannel.sendClientHello(ClientHello(protocolVersion: .v1_0, agentName: "NoctilucaClient TEST"))
            
            for await event in mainChannel.events {
                switch event {
                case .receivedServerHello(let message):
                    self.loggable?.log("서버로부터 환영 메시지를 받았습니다: 프로토콜 버전 \(message.protocolVersion.rawValue), MOTD: \(message.motd ?? "없음")")
                    logger.info("Received ServerHello: protocolVersion=\(message.protocolVersion), serverName=\(message.serverName)")
                case .receivedAuthChallenge(let authChallenge):
                    logger.info("Received AuthChallenge: acceptedMethods=\(authChallenge.acceptedMethods), message=\(authChallenge.message ?? "nil")")
                    self.loggable?.log("서버로부터 인증 챌린지를 받았습니다: \(authChallenge.message ?? "(메시지 없음)")")
                    self.delegate?.noctilucaClient(self, didReceiveAuthChallenge: authChallenge)
                default:
                    break
                }
            }
        }
    }
}
