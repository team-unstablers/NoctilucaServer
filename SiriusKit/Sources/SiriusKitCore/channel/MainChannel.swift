//
//  MainChannel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

internal import SwiftProtobuf

public enum MainChannelEvent: Sendable {
    case receivedServerNotice(ServerNotice)
    case receivedClientHello(ClientHello)
    case receivedServerHello(ServerHello)
    case receivedGoodbye(Goodbye)

    case receivedAuthChallenge(AuthChallenge)
    case receivedAuthRequest(AuthRequest)
    case receivedAuthResponse(AuthResponse)

    case receivedPing
    case receivedPong

    /// 하위 스트림에서 치명적 오류가 발생했음을 알립니다.
    /// 대표적으로 `SiriusFrameDecoderError.frameTooLarge`가 여기로 전달됩니다.
    case streamError(any Error)
}

public final class MainChannel: Channel, ChannelEventConsumer {
    public let handle: ChannelHandle
    
    nonisolated(unsafe) public let events: AsyncStream<MainChannelEvent>
    private let continuation: AsyncStream<MainChannelEvent>.Continuation
    
    nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<MainChannel>!
    
    public init(handle: ChannelHandle) {
        self.handle = handle
        
        var continuationLocal: AsyncStream<MainChannelEvent>.Continuation!

        self.events = AsyncStream<MainChannelEvent>(MainChannelEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }

        self.continuation = continuationLocal
        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }
    
    public func handleChannelReady() async {
        
    }

    public func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        do {
            switch frame.opcode {
            case .serverNotice:
                let message = try ServerNotice.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedServerNotice(message))
                case .clientHello:
                let message = try ClientHello.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedClientHello(message))
                case .serverHello:
                let message = try ServerHello.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedServerHello(message))
                case .goodbye:
                let message = try Goodbye.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedGoodbye(message))
                case .authChallenge:
                let message = try AuthChallenge.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedAuthChallenge(message))
                case .authRequest:
                let message = try AuthRequest.fromProtobufBytes(frame.data)
                self.continuation.yield(.receivedAuthRequest(message))
                case .authResponse:
                let message = try AuthResponse.fromProtobufBytes(frame.data)
                continuation.yield(.receivedAuthResponse(message))
                case .ping:
                self.continuation.yield(.receivedPing)
                case .pong:
                self.continuation.yield(.receivedPong)

            default:
                // TODO: 접속을 끊어야 하는지, 아니면 뭘 어떻게 해야 할지?
                break
            }
        } catch is SwiftProtobufError {
            // 프로토콜 오류이므로 스트림을 닫는다
            Task {
                // FIXME: 메인 채널의 문제이므로 연결 자체를 끊어야 함
                try await self.handle.close()
            }
        } catch {
            // ?
        }
    }
    
    public func handleError(error: any Error) async {
        self.continuation.yield(.streamError(error))
        self.continuation.finish()
    }

    public func handleStreamClose() async {
        self.continuation.finish()
    }

}

public extension MainChannel {
    func sendServerNotice(_ payload: ServerNotice) async throws {
        try await self.handle.send(opcode: .serverNotice, message: payload)
    }

    func sendServerHello(_ payload: ServerHello) async throws {
        try await self.handle.send(opcode: .serverHello, message: payload)
    }

    func sendClientHello(_ payload: ClientHello) async throws {
        try await self.handle.send(opcode: .clientHello, message: payload)
    }

    func sendAuthChallenge(_ payload: AuthChallenge) async throws {
        try await self.handle.send(opcode: .authChallenge, message: payload)
    }

    func sendAuthRequest(_ payload: AuthRequest) async throws {
        try await self.handle.send(opcode: .authRequest, message: payload)
    }

    func sendAuthResponse(_ payload: AuthResponse) async throws {
        try await self.handle.send(opcode: .authResponse, message: payload)
    }

    func sendGoodbye(_ payload: Goodbye) async throws {
        try await self.handle.send(opcode: .goodbye, message: payload)
    }
}
