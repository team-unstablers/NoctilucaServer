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

protocol SiriusMessage<ProtobufMessage> {
    associatedtype ProtobufMessage: SwiftProtobuf.Message
    
    func toProtobufMessage() -> ProtobufMessage
    
    init(from protobufMessage: ProtobufMessage) throws
}

extension SiriusMessage {
    func serialize() throws -> Data {
        let protobufMessage = self.toProtobufMessage()
        return try protobufMessage.serializedData()
    }
}
