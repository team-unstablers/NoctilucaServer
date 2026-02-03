//
//  ClientRoleMsQuicTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import MsQuic
import SwiftMsQuicHelper
import SiriusKitCore

enum ClientRoleMsQuicTransportError: Error {
    case notConnected
    case connectionFailed
    case streamOpenFailed
    case registrationFailed
    case configurationFailed
}

/// MsQuic 기반 클라이언트 트랜스포트 구현
///
/// 서버에 QUIC 연결을 수립하고 스트림을 관리합니다.
/// `ClientRoleTransport` 프로토콜을 구현합니다.
actor ClientRoleMsQuicTransport: ClientRoleTransport {
    nonisolated let id: ClientRoleTransportIdentifier = ClientRoleTransportIdentifier()
    nonisolated(unsafe) weak var delegate: ClientRoleTransportDelegate?

    private let host: String
    private let port: UInt16
    private let alpn: SiriusQUICAlpn

    private var registration: QuicRegistration?
    private var configuration: QuicConfiguration?
    private var connection: QuicConnection?

    private var streams: [StreamIdentifier: ClientRoleMsQuicStream] = [:]
    private var isFinalized: Bool = false

    /// 인증서 검증을 비활성화할지 여부 (개발용)
    /// 프로덕션에서는 false로 설정하고 delegate를 통해 검증해야 함
    var disableCertificateValidation: Bool = true

    init(host: String, port: UInt16, alpn: SiriusQUICAlpn = .siriusV1) {
        self.host = host
        self.port = port
        self.alpn = alpn
    }

    // MARK: - ClientRoleTransport Protocol

    func connect() async throws {
        // 1. MsQuic API 초기화 (전역적으로 한 번만 호출됨)
        _ = SwiftMsQuicAPI.open()

        // 2. Registration 생성
        let regConfig = QuicRegistrationConfig(
            appName: "SiriusKitClient-MsQuic",
            executionProfile: .lowLatency
        )
        let registration = try QuicRegistration(config: regConfig)
        self.registration = registration

        // 3. Configuration 생성
        var settings = QuicSettings()
        settings.idleTimeoutMs = 30000
        settings.peerBidiStreamCount = 128

        let configuration = try QuicConfiguration(
            registration: registration,
            alpnBuffers: [alpn.rawValue],
            settings: settings
        )
        self.configuration = configuration

        // 4. TLS Credential 설정 (클라이언트 모드)
        var credentialFlags: QuicCredentialFlags = [.client, .noCertificateValidation]
        if disableCertificateValidation {
            credentialFlags.insert(.noCertificateValidation)
        }

        let credential = QuicCredentialConfig(
            type: .none,
            flags: credentialFlags
        )
        try configuration.loadCredential(credential)

        // 5. Connection 생성 및 시작
        let connection = try QuicConnection(registration: registration)
        self.connection = connection

        // 6. 이벤트 핸들러 설정
        await setupEventHandlers(connection)

        // 7. 연결 시작
        
        try await connection.start(
            configuration: configuration,
            serverName: host,
            serverPort: port
        )

        // 연결 완료 알림
        if let delegate = self.delegate {
            await delegate.clientTransportDidEstablishConnection(self)
        }
    }

    func disconnect() async {
        guard !isFinalized else {
            return
        }

        self.isFinalized = true

        // 모든 스트림 종료
        let snapshot = Array(self.streams.values)
        self.streams.removeAll()

        for stream in snapshot {
            try? await stream.close()
        }

        // 연결 종료
        if let connection = self.connection {
            await connection.shutdown()
            self.connection = nil
        }

        // 리소스 정리
        self.configuration = nil
        self.registration = nil

        if let delegate = self.delegate {
            await delegate.clientTransportDidClose(self)
        }
    }

    func openStream() async -> Result<SiriusKitCore.Stream, TransportLayerError> {
        guard let connection = self.connection, connection.state == .connected else {
            return .failure(.openStreamFailed(error: ClientRoleMsQuicTransportError.notConnected))
        }

        do {
            let quicStream = try connection.openStream()
            try await quicStream.start()

            let stream = ClientRoleMsQuicStream(
                quicStream: quicStream,
                transport: self,
                identifier: StreamIdentifier()
            )

            registerStream(stream)
            return .success(stream)
        } catch {
            return .failure(.openStreamFailed(error: error))
        }
    }

    // MARK: - Internal Stream Management

    internal func registerStream(_ stream: ClientRoleMsQuicStream) {
        let streamId = stream.id
        guard !self.streams.keys.contains(streamId) else {
            return
        }

        self.streams.updateValue(stream, forKey: streamId)
    }

    internal func unregisterStream(_ stream: ClientRoleMsQuicStream) {
        guard self.streams.keys.contains(stream.id) else {
            return
        }

        self.streams.removeValue(forKey: stream.id)
    }

    // MARK: - Event Handlers

    private func setupEventHandlers(_ connection: QuicConnection) async {
        // 연결 이벤트 핸들러
        connection.onEvent { [weak self] _, event in
            guard let self = self else { return .success }

            switch event {
            case .shutdownInitiatedByPeer(let errorCode):
                Task {
                    await self.handleConnectionShutdown(errorCode: errorCode)
                }
            case .shutdownInitiatedByTransport(_, let errorCode):
                Task {
                    await self.handleConnectionShutdown(errorCode: errorCode)
                }
            case .shutdownComplete:
                Task {
                    await self.handleConnectionClosed()
                }
            default:
                break
            }

            return .success
        }

        // 피어 스트림 핸들러
        connection.onPeerStreamStarted { [weak self] _, quicStream in
            guard let self = self else { return }
            await self.handlePeerStream(quicStream)
        }
    }

    private func handlePeerStream(_ quicStream: QuicStream) async {
        let stream = ClientRoleMsQuicStream(
            quicStream: quicStream,
            transport: self,
            identifier: StreamIdentifier()
        )

        registerStream(stream)

        if let delegate = self.delegate {
            do {
                try await delegate.clientTransportDidOpenRemoteStream(self, stream: stream)
            } catch {
                await delegate.clientTransport(self, didEncounterError: error)
            }
        }
    }

    private func handleConnectionShutdown(errorCode: UInt64) async {
        if let delegate = self.delegate {
            let error = ClientRoleMsQuicTransportError.connectionFailed
            await delegate.clientTransport(self, didEncounterError: error)
        }
        await disconnect()
    }

    private func handleConnectionClosed() async {
        await disconnect()
    }
}

// MARK: - Hashable & Equatable

extension ClientRoleMsQuicTransport {
    nonisolated static func == (lhs: ClientRoleMsQuicTransport, rhs: ClientRoleMsQuicTransport) -> Bool {
        return lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
