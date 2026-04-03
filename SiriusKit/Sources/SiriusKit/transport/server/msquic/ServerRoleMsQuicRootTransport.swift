//
//  ServerRoleMsQuicRootTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import MsQuic
import SwiftMsQuicHelper
import SiriusKitCore

enum ServerRoleMsQuicRootTransportError: Error, ServerRoleRootTransportError {
    case apiNotInitialized
    case registrationFailed
    case configurationFailed
    case listenerFailed
    case identityAdapterFailed(Error)
    case credentialLoadFailed
}

/// MsQuic 기반 서버 트랜스포트 레이어
///
/// Network.framework 구현체(`ServerRoleQUICRootTransport`)와 병렬로 유지되며,
/// 런타임에 선택 가능합니다.
actor ServerRoleMsQuicRootTransport: ServerRoleRootTransport {
    // MARK: - Static API Management

    /// MsQuic API를 초기화합니다.
    /// 애플리케이션 시작 시 한 번 호출해야 합니다.
    static func initialize() throws {
        try SwiftMsQuicAPI.open().throwIfFailed()
    }

    /// MsQuic API를 정리합니다.
    /// 애플리케이션 종료 시 호출해야 합니다.
    static func deinitialize() {
        SwiftMsQuicAPI.close()
    }

    // MARK: - Properties

    private let port: UInt16
    private let identity: any QUICServerIdentity

    private var registration: QuicRegistration?
    private var configuration: QuicConfiguration?
    private var listener: QuicListener?
    private var identityAdapter: MsQuicServerIdentityAdapter?

    private(set) var clients: [ServerRoleMsQuicClientTransport] = []
    private var isShuttingDown = false

    nonisolated(unsafe) weak var delegate: ServerRoleRootTransportDelegate?

    // MARK: - Initialization

    init(port: UInt16, using identity: any QUICServerIdentity) {
        self.port = port
        self.identity = identity
    }

    // MARK: - ServerRoleRootTransport Protocol

    func startup() async throws {
        self.isShuttingDown = false

        // 1. MsQuic Registration 생성
        let regConfig = QuicRegistrationConfig(
            appName: "SiriusKit-MsQuic",
            executionProfile: .lowLatency
        )

        do {
            self.registration = try QuicRegistration(config: regConfig)
        } catch {
            throw ServerRoleMsQuicRootTransportError.registrationFailed
        }

        guard let registration = self.registration else {
            throw ServerRoleMsQuicRootTransportError.registrationFailed
        }

        // 2. TLS 인증서 어댑터 생성
        self.identityAdapter = MsQuicServerIdentityAdapter(identity: identity)

        guard let identityAdapter = self.identityAdapter else {
            throw ServerRoleMsQuicRootTransportError.identityAdapterFailed(
                MsQuicServerIdentityAdapter.AdapterError.identityNotAvailable
            )
        }

        // 3. Configuration 생성 (ALPN 설정)
        var settings = QuicSettings()
        settings.idleTimeoutMs = 15000
        settings.keepAliveIntervalMs = 5000
        settings.disconnectTimeoutMs = 15000

        settings.peerBidiStreamCount = 128
        settings.migrationEnabled = true
        settings.sendBufferingEnabled = true
        settings.serverResumptionLevel = UInt8(Int(exactly: QUIC_SERVER_RESUME_AND_ZERORTT.rawValue)!)
        
        settings.pacingEnabled = false
        
        settings.ecnEnabled = true


        do {
            self.configuration = try QuicConfiguration(
                registration: registration,
                alpnBuffers: [SiriusQUICAlpn.siriusV1.rawValue],
                settings: settings
            )
        } catch {
            throw ServerRoleMsQuicRootTransportError.configurationFailed
        }

        guard let configuration = self.configuration else {
            throw ServerRoleMsQuicRootTransportError.configurationFailed
        }

        // 4. TLS Credential 로드
        do {
            let credential = try await identityAdapter.createCredentialConfig()
            do {
                try configuration.loadCredential(credential)
            } catch {
                throw ServerRoleMsQuicRootTransportError.credentialLoadFailed
            }
        } catch {
            if error is ServerRoleMsQuicRootTransportError {
                throw error
            }
            
            throw ServerRoleMsQuicRootTransportError.identityAdapterFailed(error)
        }
        
        // 5. Listener 생성 및 시작
        do {
            self.listener = try QuicListener(registration: registration)
        } catch {
            throw ServerRoleMsQuicRootTransportError.listenerFailed
        }

        guard let listener = self.listener else {
            throw ServerRoleMsQuicRootTransportError.listenerFailed
        }

        // 연결 수락 핸들러 설정
        listener.onNewConnection { [weak self] _, connectionInfo in
            guard let self = self else {
                throw QuicError.invalidState
            }

            do {
                return try self.handleNewConnection(
                    connectionInfo: connectionInfo,
                    configuration: configuration
                )
            } catch {
                Task { await self.notifyAcceptFailure(error) }
                throw error
            }
        }

        // 리스너 시작
        let localAddress = QuicAddress(port: port, family: .unspecified)
        try listener.start(
            alpnBuffers: [SiriusQUICAlpn.siriusV1.rawValue],
            localAddress: localAddress
        )

        delegate?.serverTransportDidStartListening(self)
    }

    func shutdown() async throws {
        guard !self.isShuttingDown else {
            return
        }

        self.isShuttingDown = true

        // 1. Listener 중지
        if let listener = self.listener {
            await listener.stop()
            self.listener = nil
        }

        // 2. 모든 클라이언트 연결 종료
        let clientSnapshot = self.clients
        self.clients.removeAll()

        await withTaskGroup(of: Void.self) { group in
            for client in clientSnapshot {
                group.addTask {
                    await client.disconnect()
                }
            }
        }

        // 3. Configuration 해제 (deinit에서 자동 처리)
        self.configuration = nil

        // 4. Identity adapter 해제 (임시 파일 정리)
        self.identityAdapter = nil

        // 5. Registration 해제 (deinit에서 자동 처리)
        self.registration = nil

        delegate?.serverTransportDidStopListening(self)
    }

    // MARK: - Connection Handling

    private nonisolated func handleNewConnection(
        connectionInfo: QuicListenerEvent.NewConnectionInfo,
        configuration: QuicConfiguration
    ) throws -> QuicConnection? {
        // 새 QuicConnection 래퍼 생성
        let quicConnection: QuicConnection
        do {
            quicConnection = try QuicConnection(
                handle: connectionInfo.connection,
                configuration: configuration
            )
            
            try quicConnection.setStreamSchedulingScheme(.roundRobin)
        } catch {
            throw error
        }

        // ServerRoleMsQuicClientTransport 생성
        let clientTransport = ServerRoleMsQuicClientTransport(
            connection: quicConnection,
            serverTransport: self,
            remoteEndpoint: SREndpoint(msQuicAddress: connectionInfo.remoteAddress),
            id: ServerRoleClientTransportIdentifier()
        )

        installConnectionHandlers(connection: quicConnection, clientTransport: clientTransport)
        Task { await self.registerClientTransport(clientTransport) }

        return quicConnection
    }

    internal func registerClientTransport(_ transport: ServerRoleMsQuicClientTransport) async {
        guard !self.isShuttingDown else {
            await transport.disconnect()
            return
        }

        guard !transport.isClosed else {
            return
        }

        self.clients.append(transport)

        // 델리게이트 콜백 (QUICClientTransportDelegate 설정할 타이밍 제공)
        delegate?.serverTransportDidAcceptConnection(self, clientTransport: transport)

        guard !transport.isClosed else {
            self.clients.removeAll { $0.id == transport.id }
            return
        }

        await transport.start()
    }

    internal func unregisterClientTransport(_ transport: ServerRoleMsQuicClientTransport) async {
        self.clients.removeAll { $0.id == transport.id }
    }

    private nonisolated func installConnectionHandlers(
        connection: QuicConnection,
        clientTransport: ServerRoleMsQuicClientTransport
    ) {
        connection.onEvent { [weak clientTransport] _, event in
            guard let clientTransport = clientTransport else { return .success }

            switch event {
            case .shutdownInitiatedByPeer, .shutdownInitiatedByTransport:
                Task {
                    await clientTransport.handleConnectionShutdown()
                }
            case .peerAddressChanged(let address):
                Task {
                    await clientTransport.handlePeerAddressChanged(address)
                }
            default:
                break
            }

            return .success
        }

        connection.onPeerStreamStarted { [weak clientTransport] _, quicStream, flags in
            // TODO: flags은 무조건 bidirectional 해야 한다
            guard let clientTransport = clientTransport else { return }
            await clientTransport.handlePeerStream(quicStream)
        }
    }

    private func notifyAcceptFailure(_ error: Error) async {
        delegate?.serverTransportDidFailToAcceptConnection(self, error: error)
    }
}
