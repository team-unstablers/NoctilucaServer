//
//  cursor+Sirius.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation
import SwiftProtobuf


public extension MessageOpcode {
    static let subscribeCursorEventsRequest: MessageOpcode = .init(rawValue: 0x8601)
    static let subscribeCursorEventsResponse: MessageOpcode = .init(rawValue: 0x8602)
    static let unsubscribeCursorEventsRequest: MessageOpcode = .init(rawValue: 0x8603)
    static let unsubscribeCursorEventsResponse: MessageOpcode = .init(rawValue: 0x8604)
    
    static let cursorEvent: MessageOpcode = .init(rawValue: 0x8611)
}

public struct SubscribeCursorEventsRequest: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_SubscribeCursorEventsRequest
    
    public let requestID: UInt64
    public let flags: UInt32
    
    public init(requestID: UInt64, flags: UInt32) {
        self.requestID = requestID
        self.flags = flags
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.requestID = protobufMessage.requestID
        self.flags = protobufMessage.flags
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.requestID = self.requestID
        message.flags = self.flags

        return message
    }
}

public struct SubscribeCursorEventsResponse: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_SubscribeCursorEventsResponse
    
    public let requestID: UInt64
    public let subscriptionID: UUID
    
    public init(requestID: UInt64, subscriptionID: UUID) {
        self.requestID = requestID
        self.subscriptionID = subscriptionID
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.requestID = protobufMessage.requestID
        self.subscriptionID = UUID(msgdef: protobufMessage.subscriptionID)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.requestID = self.requestID
        message.subscriptionID = self.subscriptionID.asMsgDef()

        return message
    }
}


public struct UnsubscribeCursorEventsRequest: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_UnsubscribeCursorEventsRequest
    
    public let requestID: UInt64
    public let subscriptionID: UUID
    
    public init(requestID: UInt64, subscriptionID: UUID) {
        self.requestID = requestID
        self.subscriptionID = subscriptionID
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.requestID = protobufMessage.requestID
        self.subscriptionID = UUID(msgdef: protobufMessage.subscriptionID)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.requestID = self.requestID
        message.subscriptionID = self.subscriptionID.asMsgDef()

        return message
    }
}

public struct UnsubscribeCursorEventsResponse: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_UnsubscribeCursorEventsResponse
    
    public let requestID: UInt64
    public let subscriptionID: UUID
    public let isSuccess: Bool
    
    public init(requestID: UInt64, subscriptionID: UUID, isSuccess: Bool) {
        self.requestID = requestID
        self.subscriptionID = subscriptionID
        self.isSuccess = isSuccess
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.requestID = protobufMessage.requestID
        self.subscriptionID = UUID(msgdef: protobufMessage.subscriptionID)
        self.isSuccess = protobufMessage.isSuccess
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.requestID = self.requestID
        message.subscriptionID = self.subscriptionID.asMsgDef()
        message.isSuccess = self.isSuccess

        return message
    }
}


public struct CursorEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_CursorEvent
    
    public let cursorType: UInt64
    public let mimeType: String
    public let size: SRSize
    public let imageData: Data
    
    public init(cursorType: UInt64, mimeType: String, size: SRSize, imageData: Data) {
        self.cursorType = cursorType
        self.mimeType = mimeType
        self.size = size
        self.imageData = imageData
    }
    
    init(from protobufMessage: ProtobufMessage) throws {
        self.cursorType = protobufMessage.cursorType
        self.mimeType = protobufMessage.mimeType
        self.size = SRSize(from: protobufMessage.size)
        self.imageData = protobufMessage.imageData
    }
    
    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()
        
        message.cursorType = self.cursorType
        message.mimeType = self.mimeType
        message.size = self.size.toProtobufMessage()
        message.imageData = self.imageData
        
        
        return message
    }
}
