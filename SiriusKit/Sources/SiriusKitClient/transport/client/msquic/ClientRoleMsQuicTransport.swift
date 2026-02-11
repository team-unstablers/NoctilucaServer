//
//  ClientRoleMsQuicTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import Combine

import Network
import Security

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

    private let logger = SiriusLogger(category: "ClientRoleMsQuicTransport")

    internal let hostname: String
    internal let port: UInt16
    
    private let alpn: SiriusQUICAlpn

    private var registration: QuicRegistration?
    private var configuration: QuicConfiguration?
    private var connection: QuicConnection?

    private var streams: [StreamIdentifier: ClientRoleMsQuicStream] = [:]
    private var isFinalized: Bool = false
    
    private var addressMonitorCancellation: AnyCancellable?

    nonisolated(unsafe) var identity: ServerIdentity? = nil
    // 아 진짜 swift6 concurrency 개같다 ㅋㅋㅋㅋㅋㅋㅋ
    // 진짜 별걸 다 unsafe 떡칠을 해야 하네, C++는 이렇게 개같이 굴지 않았어!
    nonisolated(unsafe) var identityValidationPolicy: ServerIdentityValidationPolicy

    init(host: String, port: UInt16, alpn: SiriusQUICAlpn = .siriusV1, validationPolicy: ServerIdentityValidationPolicy) {
        self.hostname = host
        self.port = port
        self.alpn = alpn
        
        self.identityValidationPolicy = validationPolicy
    }

    // MARK: - ClientRoleTransport Protocol
    func connect() async throws {
        setupAddressMonitor()

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
        settings.idleTimeoutMs = 15000
        settings.keepAliveIntervalMs = 15000
        settings.peerBidiStreamCount = 128
        settings.migrationEnabled = true
        
        settings.pacingEnabled = false
        
        settings.streamRecvWindowDefault = 2 * 1024 * 1024
        settings.streamRecvWindowBidiLocalDefault = 2 * 1024 * 1024
        settings.streamRecvWindowBidiRemoteDefault = 2 * 1024 * 1024
        settings.streamRecvWindowUnidiDefault = 512 * 1024
        settings.connFlowControlWindow = 16 * 1024 * 1024
        settings.sendBufferingEnabled = false
        
        settings.ecnEnabled = true
        
        let configuration = try QuicConfiguration(
            registration: registration,
            alpnBuffers: [alpn.rawValue],
            settings: settings
        )
        self.configuration = configuration

        // 4. TLS Credential 설정 (클라이언트 모드)
        var credentialFlags: QuicCredentialFlags = [
            .client,
            
            // 인증서 검증은 SiriusKit 및 어플리케이션 레이어에서 수행할 것이므로
            // policy가 어떻게 설정되어 있든, 'no certificate validation' 등의 플래그는 넣지 않는다
            .indicateCertificateReceived,
            .deferCertificateValidation
        ]
        
        let credential = QuicCredentialConfig(
            type: .none,
            flags: credentialFlags
        )
        try configuration.loadCredential(credential)

        // 5. Connection 생성 및 시작
        let connection = try QuicConnection(registration: registration)
        try connection.setStreamSchedulingScheme(.roundRobin)
        
        self.connection = connection

        // 6. 이벤트 핸들러 설정
        await setupEventHandlers(connection)

        // 7. 연결 시작
        try await connection.start(
            configuration: configuration,
            serverName: hostname,
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
        self.addressMonitorCancellation?.cancel()
        self.addressMonitorCancellation = nil
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
    
    // MARK: - Connection Migration

    /// 네트워크 주소 변경을 감지하여 QUIC 커넥션 마이그레이션을 수행합니다.
    private func setupAddressMonitor() {
        self.addressMonitorCancellation = AddressMonitor.shared
            .$currentAddresses
            .dropFirst()
            .map { $0.compactMap { $0.asString() } }
            .removeDuplicates()
            .receive(on: DispatchQueue.global())
            .sink { [weak self] addresses in
                guard let self = self else { return }
                self.logger.debug("Network addresses changed: \(addresses)")

                Task {
                    do {
                        // XXX: 6to4 등으로 IPv4 <-> IPv6 패밀리 전환이 일어나면 실패할 수 있음
                        try await self.connection?.setLocalAddress(QuicAddress(port: 0, family: .unspecified))
                    } catch {
                        self.logger.error("Failed to update local address: \(error)")
                    }
                }
            }
    }
    
    nonisolated private static func validateIdentity(_ identity: ServerIdentity, using policy: ServerIdentityValidationPolicy) throws -> ServerIdentityTrustDecision {
        guard case let .sslCertificate(leaf, chain) = identity else {
            return .deny
        }
        
        if policy == .dangerouslyAllowAlwaysWithoutValidation {
            return .allow
        }
        
        // 신나는 인증서 평가 시간~ \ ' ')/
        if policy.requiresSystemValidation {
            let trust = try SecTrust.create(
                leaf: leaf,
                chain: chain,
                isServer: true,
                allowSelfSigned: policy == .dangerouslyAllowAlways
            )
            
            // try? 를 쓰는 이유는, 인증서 신뢰에 문제가 있어도 얘네는 에러를 던지기 때문이다.. -_-;;
            let result = (try? trust.evaluate()) ?? false
            
            if result {
                return .allow
            }
        }
        
        if policy.requiresAppValidation, let block = policy.validationBlock {
            return block(identity)
        }
        
        return .deny
    }

    // MARK: - Event Handlers

    private func setupEventHandlers(_ connection: QuicConnection) async {
        connection.onPeerCertificateReceived { [weak self] _, certificate, chain, _, _ in
            guard let self = self else { return .badCertificate }
            
            let identity: ServerIdentity = .sslCertificate(leaf: certificate, chain: chain)
            self.identity = identity
            
            do {
                let result = try Self.validateIdentity(identity, using: self.identityValidationPolicy)
                switch result {
                case .allow:
                    return .success
                case .deny:
                    return .badCertificate
                }
            } catch {
                self.logger.error("Failed to validate server identity: \(error)")
                return .badCertificate
            }
        }

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
            case .peerAddressChanged(let address):
                self.logger.info("Peer address changed to: \(address.description)")

            case .localAddressChanged(let address):
                self.logger.info("Local address changed to: \(address.description)")

            case .resumptionTicketReceived(let ticket):
                self.logger.info("Received resumption ticket of size: \(ticket.count) bytes")
                
                Task {
                    try? await self.connection?.setResumptionTicket(ticket)
                }

            default:
                break
            }

            return .success
        }

        // 피어 스트림 핸들러
        connection.onPeerStreamStarted { [weak self] _, quicStream, flags in
            // TODO: reject unidirectional stream
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
