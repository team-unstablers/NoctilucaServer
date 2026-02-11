//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Combine
import Atomics

import CoreGraphics

import SiriusKitClient

enum ProjectionChannelError: Error {
    case sessionCreationCancelled
    case channelClosed
}

enum ProjectionChannelEvent: Sendable {
    /// 화면 프로젝션 세션이 생성되었습니다.
    case sessionCreated(ProjectionSession)
    /// 화면 프로젝션 세션이 종료되었습니다.
    case sessionDestroyed(UUID, reason: String)
    
    /// 오디오 프로젝션 세션이 생성되었습니다.
    case audioSessionCreated(AudioProjectionSession)
    /// 오디오 프로젝션 세션이 종료되었습니다.
    case audioSessionDestroyed(UUID, reason: String)
    
    /// 디스플레이 변경 이벤트가 발생했습니다.
    // case displayLayoutChanged() // TODO: 전체 레이아웃을 들고 있거나 하는게 좋을거같음
    
    /// 커서 이미지가 변경되었습니다.
    case cursorImageChanged(CursorImageEvent)
    
    /// 커서 위치가 변경되었습니다.
    case cursorMoved(CursorMoveEvent)
}

class ProjectionChannel: Channel {
    let logger = NoctilucaLogger(category: "ProjectionChannel")
    
    override var serviceClass: ServiceClass { .userInput }

    /// Request ID 생성을 위한 atomic 카운터
    private let requestCounter = ManagedAtomic<UInt64>(0)

    var sessions: [UUID: ProjectionSession] = [:]
    var audioSessions: [UUID: AudioProjectionSession] = [:]

    private var pendingSessions: [UUID:   (any DecodableSiriusMessage) -> Void] = [:]
    private var pendingRequests: [UInt64: (any DecodableSiriusMessage) -> Void] = [:]
    
    var displayChangesSubscriptionID: UUID? = nil
    
    let displayLayoutManager = DisplayLayoutManager()

    let events = PassthroughSubject<ProjectionChannelEvent, Never>()
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)

        assert(direction == .local, "ProjectionChannel must be opened from client side")
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        switch frame.opcode {
        case .projectionSessionCreatedEvent:
            let event = try ProjectionSessionCreatedEvent.fromProtobufBytes(frame.data)
            self.logger.info("Received ProjectionSessionCreatedEvent: sessionId=\(event.identifier)")
            
            if let continuation = self.pendingSessions[event.identifier] {
                continuation(event)
            } else {
                self.logger.warning("No pending session found for identifier: \(event.identifier)")
            }
            
        case .cursorEvent:
            let event = try CursorEvent.fromProtobufBytes(frame.data)
            try await self.handleCursorEvent(event)

        // MARK: - Displayman opcodes

        case .displayListResponse:
            let response = try DisplayListResponse.fromProtobufBytes(frame.data)
            self.dispatchResponse(requestID: response.requestID, message: response)

        case .subscribeDisplayChangesResponse:
            let response = try SubscribeDisplayChangesResponse.fromProtobufBytes(frame.data)
            self.dispatchResponse(requestID: response.requestID, message: response)

        case .displayChangedEvent:
            let event = try DisplayChangedEvent.fromProtobufBytes(frame.data)
            try await self.handleDisplayChangedEvent(event)

        // MARK: - Audio projection opcodes

        case .audioSessionCreatedEvent:
            let event = try AudioSessionCreatedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionCreatedEvent(event)

        case .audioSessionCreationFailedEvent:
            let event = try AudioSessionCreationFailedEvent.fromProtobufBytes(frame.data)
            self.logger.error("Audio session creation failed: identifier=\(event.identifier), reason=\(event.reason)")

        case .audioSessionEndedEvent:
            let event = try AudioSessionEndedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionEndedEvent(event)

        default:
            break
        }
    }
    
    /// 다음 request ID를 생성합니다.
    func nextRequestID() -> UInt64 {
        requestCounter.loadThenWrappingIncrement(ordering: .relaxed)
    }
    
    func dispatchResponse(requestID: UInt64, message: any DecodableSiriusMessage) {
        if let handler = self.pendingRequests[requestID] {
            handler(message)
            self.pendingRequests.removeValue(forKey: requestID)
        } else {
             self.logger.warning("No pending request found for requestID: \(requestID)")
        }
    }
    
    
   func sendSessionRequest<T: DecodableSiriusMessage>(
        sessionID: UUID,
        opcode: MessageOpcode,
        message: any DecodableSiriusMessage
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: ProjectionChannelError.channelClosed)
                return
            }
            
            self.pendingSessions[sessionID] = { response in
                if let typedResponse = response as? T {
                    continuation.resume(returning: typedResponse)
                } else {
                    self.logger.error("Type mismatch for request \(sessionID): expected \(T.self), got \(type(of: response))")
                    continuation.resume(throwing: ChannelError.invalidFrame)
                }
            }
            
            Task {
                try await self.send(opcode: opcode, message: message)
            }
        }
    }

    func sendRequest<T: DecodableSiriusMessage>(
        requestID: UInt64,
        opcode: MessageOpcode,
        message: any DecodableSiriusMessage
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: ProjectionChannelError.channelClosed)
                return
            }
            
            self.pendingRequests[requestID] = { response in
                if let typedResponse = response as? T {
                    continuation.resume(returning: typedResponse)
                } else {
                    self.logger.error("Type mismatch for request \(requestID): expected \(T.self), got \(type(of: response))")
                    continuation.resume(throwing: ChannelError.invalidFrame)
                }
            }
            
            Task {
                try await self.send(opcode: opcode, message: message)
            }
        }
    }
}
