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
}

protocol StreamDelegate: AnyObject {
    func streamDidReceiveData(_ stream: Stream, data: Data)
    func streamDidClose(_ stream: Stream, error: Error?)
}

class Stream {
    weak var delegate: StreamDelegate?
    
    open var id: StreamIdentifier {
        return 0
    }
    
    open func write(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) async -> Result<UInt32, StreamError> {
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
    
    open func write(_ data: Data) async -> Result<UInt32, StreamError> {
        // To be implemented by subclasses
    }
    
    open func close() async throws {
        // To be implemented by subclasses
    }
}

public struct StreamHolder {
    internal let stream: Stream
}
