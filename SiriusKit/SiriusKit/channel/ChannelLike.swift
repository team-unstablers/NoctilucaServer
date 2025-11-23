//
//  SiriusMessageSender.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import SwiftProtobuf

internal protocol ChannelLike {
    var stream: Stream { get }
}

internal extension ChannelLike {
    func send(opcode: MessageOpcode, message: (any SiriusMessage)) async throws {
        let protobufMessage = message.toProtobufMessage()
        let messageData = try protobufMessage.serializedData()
        
        let result = await self.stream.write(frame: messageData, opcode: opcode)
        
        if case .failure(let error) = result {
            throw error
        }
    }
}
