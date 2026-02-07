//
//  cursor+Sirius.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation
internal import SwiftProtobuf


public extension MessageOpcode {
    static let subscribeCursorEventsRequest: MessageOpcode = .init(rawValue: 0x80A1)
    static let subscribeCursorEventsResponse: MessageOpcode = .init(rawValue: 0x80A2)
    static let unsubscribeCursorEventsRequest: MessageOpcode = .init(rawValue: 0x80A3)
    static let unsubscribeCursorEventsResponse: MessageOpcode = .init(rawValue: 0x80A4)

    static let cursorEvent: MessageOpcode = .init(rawValue: 0x80A5)
}

public struct SubscribeCursorEventsFlags: OptionSet {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// 커서 이미지를 캐싱하지 않을 것임을 서버에 알립니다.
    /// 서버 구현체는 이 플래그가 설정된 경우, 커서 이미지를 항상 전송해야 합니다.
    public static let disableImageCache = SubscribeCursorEventsFlags(rawValue: 1 << 0)
}

public struct SubscribeCursorEventsRequest: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_SubscribeCursorEventsRequest
    
    public let requestID: UInt64
    public let flags: SubscribeCursorEventsFlags
    
    public init(requestID: UInt64, flags: SubscribeCursorEventsFlags) {
        self.requestID = requestID
        self.flags = flags
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.requestID = protobufMessage.requestID
        self.flags = SubscribeCursorEventsFlags(rawValue: protobufMessage.flags)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.requestID = self.requestID
        message.flags = self.flags.rawValue

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


public struct CursorMoveEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_CursorMoveEvent

    public let displayID: UInt32
    public let position: SRPoint

    public init(displayID: UInt32, position: SRPoint) {
        self.displayID = displayID
        self.position = position
    }

    init(from protobuf: ProtobufMessage) throws {
        self.displayID = protobuf.displayID
        self.position = SRPoint(from: protobuf.position)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.displayID = displayID
        message.position = position.toProtobufMessage()

        return message
    }
}

public struct CursorImageEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_CursorImageEvent

    public let cursorType: UInt64
    public let mimeType: String
    public let size: SRSize
    public let hotspot: SRPoint
    public let imageData: Data?

    public init(cursorType: UInt64, mimeType: String, size: SRSize, hotspot: SRPoint, imageData: Data?) {
        self.cursorType = cursorType
        self.mimeType = mimeType
        self.size = size
        self.hotspot = hotspot
        self.imageData = imageData
    }

    init(from protobuf: ProtobufMessage) throws {
        self.cursorType = protobuf.cursorType
        self.mimeType = protobuf.mimeType
        self.size = SRSize(from: protobuf.size)
        self.hotspot = SRPoint(from: protobuf.hotspot)
        self.imageData = protobuf.imageData
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.cursorType = cursorType
        message.mimeType = mimeType
        message.size = size.toProtobufMessage()
        message.hotspot = hotspot.toProtobufMessage()
        
        if let imageData = imageData {
            message.imageData = imageData
        }
        
        return message
    }
}

public struct CursorEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_CursorEvent

    public enum Event {
        case moveEvent(CursorMoveEvent)
        case imageEvent(CursorImageEvent)
        case none
    }

    public let event: Event

    public init(event: Event) {
        self.event = event
    }

    init(from protobuf: ProtobufMessage) throws {
        switch protobuf.event {
        case .moveEvent(let v):
            self.event = .moveEvent(try CursorMoveEvent(from: v))
        case .imageEvent(let v):
            self.event = .imageEvent(try CursorImageEvent(from: v))
        case .none:
            self.event = .none
        }
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        switch self.event {
        case .moveEvent(let val):
            message.event = .moveEvent(val.toProtobufMessage())
        case .imageEvent(let val):
            message.event = .imageEvent(val.toProtobufMessage())
        case .none:
            break
        }

        return message
    }
}
