//
//  Stream.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public typealias StreamIdentifier = UUID

public enum StreamError: Error {
    case notImplemented
    case endOfStream

    case streamClosed
    case aborted
    case resourceExhausted
    case writeFailed(Error)
}

public enum StreamEvent: Sendable {
    case frame(SiriusFrame)
    case closed
    case error(Error)
}

open class Stream: @unchecked Sendable {
    public let events: AsyncStream<StreamEvent>
    public let continuation: AsyncStream<StreamEvent>.Continuation

    package init() {
        var continuationLocal: AsyncStream<StreamEvent>.Continuation!

        self.events = AsyncStream<StreamEvent>(StreamEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }

        self.continuation = continuationLocal
    }

    open func id() -> StreamIdentifier {
        return .zero
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
        return .failure(.notImplemented)
    }

    /// Serializes a Sirius frame and queues it for sending without waiting for completion.
    ///
    /// MsQuic guarantees FIFO ordering, so multiple calls are sent in order.
    /// Subclasses that support non-blocking send should override ``writeNonBlocking(_:)``.
    open func writeNonBlocking(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) -> Result<UInt32, StreamError> {
        let opcodeRaw = opcode.rawValue.bigEndian
        let length = (length ?? UInt32(data.count)).bigEndian

        var frameData = Data()

        withUnsafeBytes(of: opcodeRaw) { opcodeBytes in
            frameData.append(contentsOf: opcodeBytes)
        }

        withUnsafeBytes(of: length) { lengthBytes in
            frameData.append(contentsOf: lengthBytes)
        }

        frameData.append(data)

        return writeNonBlocking(frameData)
    }

    open func writeNonBlocking(_ data: Data) -> Result<UInt32, StreamError> {
        // To be implemented by subclasses
        return .failure(.notImplemented)
    }

    open func close() async throws {
        // To be implemented by subclasses
    }
    
    open func setServiceClass(_ serviceClass: ServiceClass) async throws {
        // To be implemented by subclasses
    }
}

public struct StreamHolder: Sendable {
    package let stream: Stream
}
