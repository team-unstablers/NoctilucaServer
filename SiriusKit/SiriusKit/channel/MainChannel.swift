//
//  MainChannel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

import SwiftProtobuf

public enum MainChannelEvent {
    case receivedServerNotice(ServerNotice)
    case receivedClientHello(ClientHello)
    case receivedServerHello(ServerHello)
    
    case receivedAuthChallenge(AuthChallenge)
    case receivedAuthRequest(AuthRequest)
    case receivedAuthResponse(AuthResponse)
    
    case receivedPing
    case receivedPong
}

public class MainChannel: Channel {
    public let events: AsyncStream<MainChannelEvent>
    let continuation: AsyncStream<MainChannelEvent>.Continuation
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        var continuationLocal: AsyncStream<MainChannelEvent>.Continuation!
        
        self.events = AsyncStream<MainChannelEvent>(MainChannelEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal

        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    public override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
            
        do {
            switch frame.opcode {
            case .serverNotice:
                let message = try ServerNotice.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedServerNotice(message))
                break
            case .clientHello:
                let message = try ClientHello.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedClientHello(message))
                break
            case .serverHello:
                let message = try ServerHello.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedServerHello(message))
                break
            
            case .authChallenge:
                let message = try AuthChallenge.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedAuthChallenge(message))
                break
            case .authRequest:
                let message = try AuthRequest.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedAuthRequest(message))
                break
            case .authResponse:
                let message = try AuthResponse.fromProtobufBytes(frame.data)
                continuation.yield(.receivedAuthResponse(message))
                break
                
            case .ping:
                self.continuation.yield(.receivedPing)
                break
            case .pong:
                self.continuation.yield(.receivedPong)
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
    
    override public func handleStreamClose() {
        self.continuation.finish()
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
