//
//  Channel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SwiftProtobuf



public class Channel {
    public protocol HasFeature {
        var feature: SiriusFeature { get }
    }
    
    private let stream: Stream
    
    required init(stream: Stream) {
        self.stream = stream
        self.stream.delegate = self
    }
    
    public func close() async throws {
        try await self.stream.close()
    }
    
    func send(opcode: MessageOpcode, message: (any SiriusMessage)) async throws {
        let protobufMessage = message.toProtobufMessage()
        
        var data = Data()
        
        var opcodeRaw = opcode.rawValue.bigEndian
        withUnsafeBytes(of: &opcodeRaw) { opcodeBytes in
            data.append(contentsOf: opcodeBytes)
        }
        
        let messageData = try protobufMessage.serializedData()
        data.append(messageData)
        
        _ = await self.stream.write(data)
    }
    
    func handleData(opcode: MessageOpcode, data: Data) {
        // to be overridden by subclasses
    }
    
    func handleStreamClose(error: (any Error)?) {
        // to be overridden by subclasses
    }
}

extension Channel: StreamDelegate {
    func streamDidReceiveData(_ stream: Stream, data: Data) {
        self.handleData(opcode: .init(rawValue: 0x00), data: data) // FIXME
    }
    
    func streamDidClose(_ stream: Stream, error: (any Error)?) {
        self.handleStreamClose(error: error)
    }
}

internal extension Channel {
    
    // helper method
    func blockUntilReceiveData() async throws -> (MessageOpcode, Data) {
        // FIXME: implement me
    }
}
