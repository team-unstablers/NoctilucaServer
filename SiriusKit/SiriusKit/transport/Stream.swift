//
//  Stream.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

typealias StreamIdentifier = UInt64

enum StreamError: Error {
    case notImplemented
    case endOfStream
}

enum StreamEvent {
    case frame(SiriusFrame)
    case closed
    case error(Error)
}

class Stream {
    let events: AsyncStream<StreamEvent>
    let continuation: AsyncStream<StreamEvent>.Continuation
    
    init() {
        var continuationLocal: AsyncStream<StreamEvent>.Continuation!
        
        self.events = AsyncStream<StreamEvent>(StreamEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
    }
    
    var id: StreamIdentifier {
        return 0
    }
    
    func write(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) async -> Result<UInt32, StreamError> {
        let opcodeRaw = opcode.rawValue.bigEndian
        let length = (length ?? UInt32(data.count)).bigEndian
        
        var frameData = Data()
        
        // TODO: Data+append(uint32: UInt32) extension
        
        withUnsafeBytes(of: opcodeRaw) { opcodeBytes in
            frameData.append(contentsOf: opcodeBytes)
        }
        
        withUnsafeBytes(of: length) { lengthBytes in
            frameData.append(contentsOf: lengthBytes)
        }
        
        frameData.append(data)
        
        return await write(frameData)
    }
    
    func write(_ data: Data) async -> Result<UInt32, StreamError> {
        // To be implemented by subclasses
        return .failure(.notImplemented)
    }
    
    func close() async throws {
        // To be implemented by subclasses
    }
}

public struct StreamHolder {
    internal let stream: Stream
}
