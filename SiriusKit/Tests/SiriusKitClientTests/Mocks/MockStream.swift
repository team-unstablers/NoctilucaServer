//
//  MockStream.swift
//  SiriusKitClientTests
//

import Foundation
@testable import SiriusKitCore

final class MockStream: SiriusKitCore.Stream {
    private(set) var writtenFrames: [(opcode: MessageOpcode, data: Data)] = []
    private(set) var isClosed = false

    var writeError: StreamError?

    override func write(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) async -> Result<UInt32, StreamError> {
        writtenFrames.append((opcode: opcode, data: data))

        if let error = writeError {
            return .failure(error)
        }
        return .success(UInt32(data.count))
    }

    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        if let error = writeError {
            return .failure(error)
        }
        return .success(UInt32(data.count))
    }

    override func close() async throws {
        isClosed = true
        continuation.finish()
    }

    override func setServiceClass(_ serviceClass: ServiceClass) async throws {
        // no-op
    }

    // MARK: - Injection

    func injectFrame(_ frame: SiriusFrame) {
        continuation.yield(.frame(frame))
    }

    func injectError(_ error: Error) {
        continuation.yield(.error(error))
    }

    func injectClose() {
        continuation.yield(.closed)
    }

    // MARK: - Query Helpers

    func frames(withOpcode opcode: MessageOpcode) -> [(opcode: MessageOpcode, data: Data)] {
        writtenFrames.filter { $0.opcode == opcode }
    }

    func firstFrame(withOpcode opcode: MessageOpcode) -> (opcode: MessageOpcode, data: Data)? {
        writtenFrames.first { $0.opcode == opcode }
    }

    func decodeFirstMessage<T: DecodableSiriusMessage>(
        withOpcode opcode: MessageOpcode,
        as type: T.Type
    ) throws -> T? {
        guard let frame = firstFrame(withOpcode: opcode) else { return nil }
        return try T.fromProtobufBytes(frame.data)
    }
}
