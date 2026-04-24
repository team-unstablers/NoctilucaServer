//
//  ServerRoleMsQuicStream.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import MsQuic
import SwiftMsQuic

internal import Atomics
import SiriusKitCore

/// MsQuic 기반 스트림 구현
///
/// `QuicStream`을 래핑하여 SiriusKit의 `Stream` 클래스를 구현합니다.
/// 프레이밍 규칙: [opcode: 2바이트 BE] [length: 4바이트 BE] [payload: length 바이트]
class ServerRoleMsQuicStream: SiriusKitCore.Stream {
    let quicStream: QuicStream
    private weak var transport: ServerRoleMsQuicClientTransport?

    private var receiveTask: Task<Void, Error>?
    private let isClosed = ManagedAtomic(false)
    
    private var _id: StreamIdentifier = .zero

    init(quicStream: QuicStream, transport: ServerRoleMsQuicClientTransport, identifier: StreamIdentifier = StreamIdentifier()) {
        self.quicStream = quicStream
        self.transport = transport

        super.init()
        self._id = identifier

        // 수신 루프 시작
        startReceiveLoop()
    }

    // MARK: - Stream Protocol Overrides
    
    override func id() -> StreamIdentifier {
        return _id
    }

    override func close() async throws {
        if self.isClosed.exchange(true, ordering: .acquiringAndReleasing) {
            return
        }

        // Graceful shutdown
        await quicStream.shutdown(flags: .abort, errorCode: 0)

        receiveTask?.cancel()
        self.continuation.yield(with: .success(.closed))
        self.continuation.finish()
        await transport?.unregisterStream(self)
    }

    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        do {
            try await quicStream.send(data)
            return .success(UInt32(data.count))
        } catch {
            Task { [weak self] in
                try? await self?.close()
            }
            return .failure(mapQuicError(error))
        }
    }

    override func writeNonBlocking(_ data: Data) -> Result<UInt32, StreamError> {
        do {
            try quicStream.send(data)
            return .success(UInt32(data.count))
        } catch {
            Task { [weak self] in
                try? await self?.close()
            }
            return .failure(mapQuicError(error))
        }
    }

    private func mapQuicError(_ error: Error) -> StreamError {
        guard let quicError = error as? QuicError else {
            return .writeFailed(error)
        }
        switch quicError {
        case .invalidState:
            return .streamClosed
        case .aborted:
            return .aborted
        case .outOfMemory:
            return .resourceExhausted
        default:
            return .writeFailed(error)
        }
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
        var decoder = SiriusFrameStreamDecoder()

        for try await chunk in quicStream.receive {
            decoder.append(chunk)
            while let frame = try decoder.nextFrame() {
                self.continuation.yield(with: .success(.frame(frame)))
            }
        }

        // 스트림 종료
        throw StreamError.endOfStream
    }

    // MARK: - Finalization

    private func finalize(event: StreamEvent) async {
        if self.isClosed.exchange(true, ordering: .acquiringAndReleasing) {
            return
        }

        receiveTask?.cancel()

        self.continuation.yield(with: .success(event))
        self.continuation.finish()

        await transport?.unregisterStream(self)
    }
}

// MARK: - Hashable & Equatable

extension ServerRoleMsQuicStream: Hashable, Equatable {
    static func == (lhs: ServerRoleMsQuicStream, rhs: ServerRoleMsQuicStream) -> Bool {
        return lhs.id() == rhs.id()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id())
    }
}
