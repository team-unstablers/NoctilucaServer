//
//  ServerRoleMsQuicClientTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import MsQuic
import SwiftMsQuicHelper

internal import Atomics
import SiriusKitCore

enum ServerRoleMsQuicClientTransportError: Error {
    case streamOpenFailed
    case connectionNotReady
}

/// MsQuic 기반 클라이언트 연결 관리 트랜스포트
///
/// 서버가 수락한 개별 클라이언트 연결을 나타냅니다.
/// `QuicConnection`을 래핑하여 `ServerRoleClientTransport` 프로토콜을 구현합니다.
actor ServerRoleMsQuicClientTransport: ServerRoleClientTransport {
    nonisolated let id: ServerRoleClientTransportIdentifier
    nonisolated(unsafe) weak var delegate: ServerRoleClientTransportDelegate?

    private static let logger = SiriusLogger(category: "ServerRoleMsQuicClientTransport")

    let connection: QuicConnection
    private weak var serverTransport: ServerRoleMsQuicRootTransport?

    private var streams: [StreamIdentifier: ServerRoleMsQuicStream] = [:]
    nonisolated(unsafe) private let isFinalized = ManagedAtomic(false)

    nonisolated var remoteAddress: String? {
        // MsQuic connection에서 원격 주소를 얻는 것은 현재 지원하지 않음
        // 필요시 QuicConnection에 해당 기능 추가 필요
        return nil
    }

    init(connection: QuicConnection, serverTransport: ServerRoleMsQuicRootTransport, id: ServerRoleClientTransportIdentifier) {
        self.id = id
        self.connection = connection
        self.serverTransport = serverTransport
    }

    deinit {
        if !isFinalized.load(ordering: .acquiring) {
            Self.logger.warning("MsQuic client transport deinitialized without disconnect. id=\(self.id)")
        }
    }

    // MARK: - TransportLayer Protocol

    func disconnect() async {
        if isFinalized.exchange(true, ordering: .acquiring) {
            return
        }

        // 모든 스트림 종료
        let snapshot = Array(self.streams.values)
        self.streams.removeAll()

        for stream in snapshot {
            try? await stream.close()
        }

        // 연결 종료
        do {
            try await connection.shutdown(timeoutMs: 5000, force: true)
        } catch {
            Self.logger.warning("MsQuic connection shutdown timed out; forcing close. error=\(error)")
        }

        await delegate?.clientTransportDidClose(self)
        if let serverTransport = serverTransport {
            await serverTransport.unregisterClientTransport(self)
        }
    }

    func openStream() async -> Result<SiriusKitCore.Stream, TransportLayerError> {
        guard connection.state == .connected else {
            return .failure(.openStreamFailed(error: ServerRoleMsQuicClientTransportError.connectionNotReady))
        }

        do {
            let quicStream = try connection.openStream()
            try await quicStream.start()

            let stream = ServerRoleMsQuicStream(
                quicStream: quicStream,
                transport: self,
                identifier: StreamIdentifier()
            )

            await registerStream(stream)
            return .success(stream)
        } catch {
            return .failure(.openStreamFailed(error: error))
        }
    }

    // MARK: - Internal Setup

    internal func setup() async {
        // 연결 핸들러는 리스너 콜백에서 즉시 설치됨 (동기 수락 요구사항 대응)
    }

    internal func start() async {
        // MsQuic connection은 이미 시작됨 (서버가 수락한 연결)
        // 추가 시작 로직 필요 없음
    }

    // MARK: - Stream Handling

    internal func handlePeerStream(_ quicStream: QuicStream) async {
        let stream = ServerRoleMsQuicStream(
            quicStream: quicStream,
            transport: self,
            identifier: StreamIdentifier()
        )

        await registerStream(stream)

        if let delegate = self.delegate {
            do {
                try await delegate.clientTransportDidOpenRemoteStream(self, stream: stream)
            } catch {
                await delegate.clientTransport(self, didEncounterError: error)
            }
        }
    }

    internal func handleConnectionShutdown() async {
        await disconnect()
    }

    internal func registerStream(_ stream: ServerRoleMsQuicStream) {
        let streamId = stream.id
        guard !self.streams.keys.contains(streamId) else {
            return
        }

        self.streams.updateValue(stream, forKey: streamId)
    }

    internal func unregisterStream(_ stream: ServerRoleMsQuicStream) {
        guard self.streams.keys.contains(stream.id) else {
            return
        }

        self.streams.removeValue(forKey: stream.id)
    }
}

// MARK: - Hashable & Equatable

extension ServerRoleMsQuicClientTransport: Hashable, Equatable {
    nonisolated static func == (lhs: ServerRoleMsQuicClientTransport, rhs: ServerRoleMsQuicClientTransport) -> Bool {
        return lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
