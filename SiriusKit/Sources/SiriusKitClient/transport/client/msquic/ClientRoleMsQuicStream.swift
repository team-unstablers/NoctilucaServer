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

    private var receiveTask: Task<Void, Error>?
    private let isClosed = ManagedAtomic(false)

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
        quicStream.shutdownSend()
        await quicStream.shutdown()
        await finalize(event: .closed)
    }

    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        let byteCount = UInt64(data.count)
        writeBackPressure.wrappingIncrement(by: byteCount, ordering: .relaxed)

        defer {
            self.writeBackPressure.wrappingDecrement(by: byteCount, ordering: .relaxed)
        }

        do {
            try await quicStream.send(data)
            return .success(UInt32(data.count))
        } catch {
            return .failure(.notImplemented) // TODO: Map error appropriately
        }
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        self.receiveTask = Task {
            do {
                try await self.receiveLoop()
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
