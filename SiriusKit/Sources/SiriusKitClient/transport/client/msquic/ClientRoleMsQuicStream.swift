//
//  ClientRoleMsQuicStream.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import MsQuic
import SwiftMsQuicHelper

import Atomics
import SiriusKitCore

/// MsQuic 기반 클라이언트 스트림 구현
///
/// `QuicStream`을 래핑하여 SiriusKit의 `Stream` 클래스를 구현합니다.
/// 프레이밍 규칙: [opcode: 2바이트 BE] [length: 4바이트 BE] [payload: length 바이트]
class ClientRoleMsQuicStream: SiriusKitCore.Stream {
    let quicStream: QuicStream
    let transport: ClientRoleMsQuicTransport

    private enum NonBufferedSendDefaults {
        static let chunkSize = 32 * 1024
        static let bootstrapWindowBytes: UInt64 = 128 * 1024
    }

    private var receiveTask: Task<Void, Error>?
    private let isClosed = ManagedAtomic(false)
    private let sendGate = NonBufferedSendGate()

    init(quicStream: QuicStream, transport: ClientRoleMsQuicTransport, identifier: StreamIdentifier = StreamIdentifier()) {
        self.quicStream = quicStream
        self.transport = transport

        super.init()
        self.id = identifier

        // 수신 루프 시작
        startReceiveLoop()
    }

    // MARK: - Stream Protocol Overrides

    override func close() async throws {
        if self.isClosed.load(ordering: .acquiring) {
            return
        }

        // Graceful shutdown
        await quicStream.shutdown(flags: .abort)
        await finalize(event: .closed)
    }

    override func write(frame data: Data, opcode: MessageOpcode, length: UInt32? = nil) async -> Result<UInt32, StreamError> {
        let header = Self.makeFrameHeader(opcode: opcode, length: length ?? UInt32(data.count))
        let chunks = Self.makeChunks(header: header, payload: data)

        return await self.sendSerialized(
            chunks: chunks,
            writtenByteCount: UInt32(header.count + data.count),
            closeOnFailure: false
        )
    }

    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        let chunks = Self.makePayloadChunks(payload: data)
        return await self.sendSerialized(
            chunks: chunks,
            writtenByteCount: UInt32(data.count),
            closeOnFailure: false
        )
    }
    
    override func setServiceClass(_ serviceClass: ServiceClass) async throws {
        try self.quicStream.setPriority(serviceClass.asMsQuicPriority)
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        self.receiveTask = Task {
            do {
                try await self.receiveLoop()
            } catch QuicError.aborted {
                try? await self.close()
            } catch {
                if let streamError = error as? StreamError, case .endOfStream = streamError {
                    try? await self.close()
                    return
                }

                await self.finalize(event: .error(error))
            }
        }
    }

    private func receiveLoop() async throws {
        // 프레임 파싱을 위한 버퍼
        var buffer = Data()

        for try await chunk in quicStream.receive {
            buffer.append(chunk)

            // 버퍼에서 완전한 프레임들을 추출
            while true {
                // 헤더 크기 확인 (opcode 2바이트 + length 4바이트 = 6바이트)
                guard buffer.count >= 6 else {
                    break
                }

                // 헤더 파싱
                let opcode = buffer.subdata(in: 0..<2).withUnsafeBytes {
                    $0.load(as: UInt16.self).bigEndian
                }
                let length = buffer.subdata(in: 2..<6).withUnsafeBytes {
                    $0.load(as: UInt32.self).bigEndian
                }

                // 전체 프레임 크기 확인
                let frameSize = 6 + Int(length)
                guard buffer.count >= frameSize else {
                    break
                }

                // 페이로드 추출
                let payload = (length > 0) ?
                    buffer.subdata(in: 6..<frameSize) :
                    Data()

                // 프레임 생성 및 이벤트 발행
                let frame = SiriusFrame(
                    opcode: MessageOpcode(rawValue: opcode),
                    length: length,
                    data: payload
                )

                self.continuation.yield(with: .success(.frame(frame)))

                // 버퍼에서 처리된 프레임 제거
                buffer.removeSubrange(0..<frameSize)
            }
        }

        // 스트림 종료
        throw StreamError.endOfStream
    }

    // MARK: - Finalization

    private func finalize(event: StreamEvent) async {
        if self.isClosed.exchange(true, ordering: .acquiring) {
            return
        }

        receiveTask?.cancel()

        self.continuation.yield(with: .success(event))
        self.continuation.finish()

        await transport.unregisterStream(self)
    }

    // MARK: - Send Helpers

    private static func makeFrameHeader(opcode: MessageOpcode, length: UInt32) -> Data {
        let opcodeRaw = opcode.rawValue.bigEndian
        let lengthRaw = length.bigEndian

        var header = Data()
        header.reserveCapacity(6)

        withUnsafeBytes(of: opcodeRaw) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: lengthRaw) { header.append(contentsOf: $0) }

        return header
    }

    private static func makeChunks(header: Data, payload: Data) -> [Data] {
        guard !payload.isEmpty else {
            return [header]
        }

        var chunks: [Data] = [header]
        chunks.append(contentsOf: makePayloadChunks(payload: payload))
        return chunks
    }

    private static func makePayloadChunks(payload: Data) -> [Data] {
        guard !payload.isEmpty else {
            return [Data()]
        }

        if payload.count <= NonBufferedSendDefaults.chunkSize {
            return [payload]
        }

        var chunks: [Data] = []
        chunks.reserveCapacity((payload.count + NonBufferedSendDefaults.chunkSize - 1) / NonBufferedSendDefaults.chunkSize)

        var start = 0
        while start < payload.count {
            let end = min(start + NonBufferedSendDefaults.chunkSize, payload.count)
            chunks.append(payload.subdata(in: start..<end))
            start = end
        }

        return chunks
    }

    private func sendSerialized(chunks: [Data], writtenByteCount: UInt32, closeOnFailure: Bool) async -> Result<UInt32, StreamError> {
        do {
            try await sendGate.withLock {
                try await quicStream.sendChunks(
                    chunks,
                    options: .init(bootstrapWindowBytes: NonBufferedSendDefaults.bootstrapWindowBytes)
                )
            }
            return .success(writtenByteCount)
        } catch {
            if closeOnFailure {
                Task { [weak self] in
                    try? await self?.close()
                }
            }
            return .failure(.notImplemented) // TODO: Map error appropriately
        }
    }
}

// MARK: - Hashable & Equatable

extension ClientRoleMsQuicStream: Hashable, Equatable {
    static func == (lhs: ClientRoleMsQuicStream, rhs: ClientRoleMsQuicStream) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private actor NonBufferedSendGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ operation: () async throws -> T) async rethrows -> T {
        await self.lock()
        defer { self.unlock() }
        return try await operation()
    }

    private func lock() async {
        guard !isLocked else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return
        }

        isLocked = true
    }

    private func unlock() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}
