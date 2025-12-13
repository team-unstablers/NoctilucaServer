//
//  SiriusMessage.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SwiftProtobuf

public enum SiriusMessageError: Error {
    case protobufDecodingError(Error)
    case protobufEncodingError(Error)
    case invalidProtobufMessage
}

public struct MessageOpcode: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UInt16
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    // client -> server
    public static let ping = MessageOpcode(rawValue: 0xFFFA)
    // server -> client
    public static let pong = MessageOpcode(rawValue: 0xFFFB)
    
    // 업그레이드된 프로토콜 메시지 (encapsulated)
    public static let encapsulatedProtocolMessage = MessageOpcode(rawValue: 0xFFFE)
}

protocol SiriusEnum<ProtobufEnum>: RawRepresentable, Equatable, Hashable where RawValue: SignedInteger {
    associatedtype ProtobufEnum: SwiftProtobuf.Enum
    
    var rawValue: RawValue { get }
    
    init(rawValue: RawValue)
    
}

protocol SiriusStruct<ProtobufMessage> {
    associatedtype ProtobufMessage: SwiftProtobuf.Message
    
    func toProtobufMessage() -> ProtobufMessage
    
    init(from protobufMessage: ProtobufMessage) throws
}

public protocol DecodableSiriusMessage {
    static func fromProtobufBytes(_ bytes: Data) throws -> Self
}

protocol SiriusMessage<ProtobufMessage>: DecodableSiriusMessage {
    associatedtype ProtobufMessage: SwiftProtobuf.Message
    
    func toProtobufMessage() -> ProtobufMessage
    
    init(from protobufMessage: ProtobufMessage) throws
}

extension MessageOpcode {
    var hexString: String {
        String(format: "0x%04X", self.rawValue)
    }
}


extension SiriusMessage {
    public static func fromProtobufBytes(_ bytes: Data) throws -> Self {
        let protobufMessage = try ProtobufMessage(serializedBytes: bytes)
        return try Self(from: protobufMessage)
    }
    
    func serialize() throws -> Data {
        let protobufMessage = self.toProtobufMessage()
        return try protobufMessage.serializedData()
    }
}

extension SiriusEnum {
    func toProtobufEnum() -> ProtobufEnum {
        ProtobufEnum(rawValue: Int(self.rawValue))!
    }
    
    static func fromProtobufEnum(_ protobufEnum: ProtobufEnum) -> Self {
        return Self(rawValue: RawValue(protobufEnum.rawValue))
    }
}

