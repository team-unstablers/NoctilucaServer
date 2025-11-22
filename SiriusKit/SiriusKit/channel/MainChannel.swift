//
//  MainChannel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

import SwiftProtobuf

public protocol MainChannelDelegate: AnyObject {
    func mainChannelDidReceiveServerNotice(_ channel: MainChannel, message: ServerNotice)
    func mainChannelDidReceiveClientHello(_ channel: MainChannel, message: ClientHello)
    func mainChannelDidReceiveServerHello(_ channel: MainChannel, message: ServerHello)
    
    func mainChannelDidReceiveAuthChallenge(_ channel: MainChannel, message: AuthChallenge)
    func mainChannelDidReceiveAuthRequest(_ channel: MainChannel, message: AuthRequest)
    func mainChannelDidReceiveAuthResponse(_ channel: MainChannel, message: AuthResponse)
}

public class MainChannel: Channel {
    public weak var delegate: MainChannelDelegate?
    
    override func handleData(opcode: MessageOpcode, data: Data) {
        do {
            switch opcode {
            case .serverNotice:
                let message = try ServerNotice.fromProtobufBytes(data)
                self.delegate?.mainChannelDidReceiveServerNotice(self, message: message)
                break
            case .clientHello:
                let message = try ClientHello.fromProtobufBytes(data)
                self.delegate?.mainChannelDidReceiveClientHello(self, message: message)
                break
            case .serverHello:
                let message = try ServerHello.fromProtobufBytes(data)
                self.delegate?.mainChannelDidReceiveServerHello(self, message: message)
                break
            
            case .authChallenge:
                let message = try AuthChallenge.fromProtobufBytes(data)
                self.delegate?.mainChannelDidReceiveAuthChallenge(self, message: message)
                break
            case .authRequest:
                let message = try AuthRequest.fromProtobufBytes(data)
                self.delegate?.mainChannelDidReceiveAuthRequest(self, message: message)
                break
            case .authResponse:
                let message = try AuthResponse.fromProtobufBytes(data)
                self.delegate?.mainChannelDidReceiveAuthResponse(self, message: message)
                break
                
            default:
                // TODO: 접속을 끊어야 하는지, 아니면 뭘 어떻게 해야 할지?
                break
            }
        } catch is SwiftProtobufError {
            // 프로토콜 오류이므로 스트림을 닫는다
            Task {
                // FIXME: 메인 채널의 문제이므로 연결 자체를 끊어야 함
                try await self.close()
            }
        } catch {
            // ?
        }
    }
    
    override func handleStreamClose(error: (any Error)?) {
        
    }
}

public extension MainChannel {
    func sendServerNotice(_ payload: ServerNotice) async throws {
        try await self.send(opcode: .serverNotice, message: payload)
    }

    func sendServerHello(_ payload: ServerHello) async throws {
        try await self.send(opcode: .serverHello, message: payload)
    }
    
    func sendClientHello(_ payload: ClientHello) async throws {
        try await self.send(opcode: .clientHello, message: payload)
    }
    
    func sendAuthChallenge(_ payload: AuthChallenge) async throws {
        try await self.send(opcode: .authChallenge, message: payload)
    }
    
    func sendAuthRequest(_ payload: AuthRequest) async throws {
        try await self.send(opcode: .authRequest, message: payload)
    }
    
    func sendAuthResponse(_ payload: AuthResponse) async throws {
        try await self.send(opcode: .authResponse, message: payload)
    }
}
