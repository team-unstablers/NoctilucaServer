//
//  MockStream.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore

/// `@unchecked Sendable` mock stream for unit tests.
///
/// 여러 Task가 동시에 `write(frame:)` / `writeNonBlocking(frame:)` 을 호출하는
/// 시나리오(예: `ChannelHandleImpl` 의 fast-path / directSend spawn path)를 테스트할 때
/// `writtenFrames` 배열 동시 수정으로 인한 data race가 발생할 수 있다.
/// 모든 상태는 `stateLock` 뒤에서 보호한다.
final class MockStream: SiriusKitCore.Stream, @unchecked Sendable {
    private let stateLock = NSLock()
    private var _writtenFrames: [(opcode: MessageOpcode, data: Data)] = []
    private var _isClosed = false

    var writtenFrames: [(opcode: MessageOpcode, data: Data)] {
        stateLock.withLock { _writtenFrames }
    }
    var isClosed: Bool {
        stateLock.withLock { _isClosed }
    }

    var writeError: StreamError?

    override func write(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) async -> Result<UInt32, StreamError> {
        stateLock.withLock {
            _writtenFrames.append((opcode: opcode, data: data))
        }

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

    override func writeNonBlocking(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) -> Result<UInt32, StreamError> {
        stateLock.withLock {
            _writtenFrames.append((opcode: opcode, data: data))
        }

        if let error = writeError {
            return .failure(error)
        }
        return .success(UInt32(data.count))
    }

    override func writeNonBlocking(_ data: Data) -> Result<UInt32, StreamError> {
        if let error = writeError {
            return .failure(error)
        }
        return .success(UInt32(data.count))
    }

    override func close() async throws {
        stateLock.withLock { _isClosed = true }
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
