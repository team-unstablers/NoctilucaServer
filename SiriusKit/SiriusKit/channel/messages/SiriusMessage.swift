//
//  SiriusMessage.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SwiftProtobuf

struct MessageOpcode: RawRepresentable, Equatable, Hashable {
    typealias RawValue = UInt16
    let rawValue: UInt16
    
    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
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

protocol SiriusMessage<ProtobufMessage> {
    associatedtype ProtobufMessage: SwiftProtobuf.Message
    
    func toProtobufMessage() -> ProtobufMessage
    
    init(from protobufMessage: ProtobufMessage) throws
}

extension SiriusMessage {
    static func fromProtobufBytes(_ bytes: Data) throws -> Self {
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
