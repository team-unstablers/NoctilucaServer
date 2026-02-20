//
//  XPCServerRoleRootTransport.swift
//  SiriusKit
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKitCore

/// noctilucad와 NSXPCConnection을 통해 통신하는 가상 루트 트랜스포트.
///
/// NoctilucaServer(Agent)에서 `SiriusServerBuilder`를 통해 생성되며,
/// 데몬으로부터 사전 인증된 클라이언트 연결을 수신한다.
///
/// ## 동작 흐름
/// 1. `startup()` 시 데몬의 Mach 서비스에 NSXPCConnection으로 연결
/// 2. `SiriusAgentXPCInterface`를 export하여 데몬이 호출할 수 있도록 함
/// 3. `agentDidStartup(uid:)`으로 데몬에 자신을 announce
/// 4. 데몬이 `acceptPreAuthenticatedClient`를 호출하면 `XPCServerRoleClientTransport`를 생성
/// 5. `shutdown()` 시 `agentWillShutdown()`으로 depart
actor XPCServerRoleRootTransport: ServerRoleRootTransport {
    nonisolated(unsafe) weak var delegate: ServerRoleRootTransportDelegate?

    private let machServiceName: String
    private var connection: NSXPCConnection?
    private var clients: [UUID: XPCServerRoleClientTransport] = [:]

    /// XPC 이벤트를 수신하는 핸들러 객체. NSObject 서브클래스여야 XPC 프로토콜을 구현할 수 있다.
    private var xpcHandler: AgentXPCHandler?

    init(machServiceName: String) {
        self.machServiceName = machServiceName
    }

    func startup() async throws {
        let conn = NSXPCConnection(machServiceName: machServiceName)
        conn.remoteObjectInterface = createSiriusDaemonXPCInterface()
        conn.exportedInterface = createSiriusAgentXPCInterface()

        let handler = AgentXPCHandler(transport: self)
        conn.exportedObject = handler
        self.xpcHandler = handler

        conn.interruptionHandler = { [weak self] in
            guard let self else { return }
            Task { await self.handleConnectionInterruption() }
        }

        conn.invalidationHandler = { [weak self] in
            guard let self else { return }
            Task { await self.handleConnectionInvalidation() }
        }

        conn.resume()
        self.connection = conn

        // 데몬에 announce
        let uid = getuid()
        let daemonProxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            guard let self else { return }
            Task { await self.delegate?.serverTransport(self, didEncounterError: error) }
            // swiftlint:disable:next force_cast
        } as! SiriusDaemonXPCInterface

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            daemonProxy.agentDidStartup(uid: uid) { _ in
                continuation.resume()
            }
        }

        delegate?.serverTransportDidStartListening(self)
    }

    func shutdown() async throws {
        // 데몬에 depart
        if let daemonProxy = connection?.remoteObjectProxy as? SiriusDaemonXPCInterface {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                daemonProxy.agentWillShutdown {
                    continuation.resume()
                }
            }
        }

        // 모든 클라이언트 정리
        let snapshot = Array(clients.values)
        clients.removeAll()
        for client in snapshot {
            await client.handleDisconnect()
        }

        connection?.invalidate()
        connection = nil
        xpcHandler = nil

        delegate?.serverTransportDidStopListening(self)
    }

    // MARK: - SiriusAgentXPCInterface 이벤트 → 내부 핸들러

    func handleAcceptPreAuthenticatedClient(
        clientID: UUID,
        metadata: SiriusXPCAuthMetadata
    ) -> Bool {
        let transport = XPCServerRoleClientTransport(
            id: clientID,
            metadata: metadata,
            rootTransport: self
        )
        clients[clientID] = transport

        delegate?.serverTransportDidAcceptConnection(self, clientTransport: transport)
        return true
    }

    func handleRemoteStreamOpen(clientID: UUID, streamID: UUID) async -> Bool {
        guard let client = clients[clientID] else { return false }
        await client.handleRemoteStreamOpen(streamID: streamID)
        return true
    }

    func handleStreamData(clientID: UUID, streamID: UUID, data: Data) async {
        guard let client = clients[clientID] else { return }
        await client.handleStreamData(streamID: streamID, data: data)
    }

    func handleStreamClose(clientID: UUID, streamID: UUID) async {
        guard let client = clients[clientID] else { return }
        await client.handleStreamClose(streamID: streamID)
    }

    func handleStreamError(clientID: UUID, streamID: UUID, description: String) async {
        guard let client = clients[clientID] else { return }
        await client.handleStreamError(streamID: streamID, description: description)
    }

    func handleClientDisconnect(clientID: UUID) async {
        guard let client = clients[clientID] else { return }
        clients.removeValue(forKey: clientID)
        await client.handleDisconnect()
    }

    // MARK: - XPCServerRoleClientTransport에서 호출하는 데몬 요청

    func requestOpenStream(clientID: UUID, streamID: UUID) async -> Bool {
        guard let daemonProxy = getDaemonProxy() else { return false }

        return await withCheckedContinuation { continuation in
            daemonProxy.openStream(
                clientID: clientID as NSUUID,
                streamID: streamID as NSUUID
            ) { success in
                continuation.resume(returning: success)
            }
        }
    }

    func requestWriteStreamData(clientID: UUID, streamID: UUID, data: Data) async -> Result<UInt32, StreamError> {
        guard let daemonProxy = getDaemonProxy() else {
            return .failure(.endOfStream)
        }

        return await withCheckedContinuation { continuation in
            daemonProxy.writeStreamData(
                clientID: clientID as NSUUID,
                streamID: streamID as NSUUID,
                data: data as NSData
            ) { bytesWritten, errorDesc in
                if let errorDesc = errorDesc as? String {
                    _ = errorDesc
                    continuation.resume(returning: .failure(.endOfStream))
                } else {
                    continuation.resume(returning: .success(bytesWritten))
                }
            }
        }
    }

    func requestCloseStream(clientID: UUID, streamID: UUID) async {
        guard let daemonProxy = getDaemonProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            daemonProxy.closeStream(
                clientID: clientID as NSUUID,
                streamID: streamID as NSUUID
            ) { _ in
                continuation.resume()
            }
        }
    }

    func requestSetStreamServiceClass(clientID: UUID, streamID: UUID, serviceClass: ServiceClass) async {
        guard let daemonProxy = getDaemonProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            daemonProxy.setStreamServiceClass(
                clientID: clientID as NSUUID,
                streamID: streamID as NSUUID,
                rawValue: serviceClass.xpcRawValue
            ) { _ in
                continuation.resume()
            }
        }
    }

    func requestDisconnectClient(_ clientID: UUID) async {
        guard let daemonProxy = getDaemonProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            daemonProxy.disconnectClient(clientID as NSUUID) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Private

    private func getDaemonProxy() -> SiriusDaemonXPCInterface? {
        connection?.remoteObjectProxy as? SiriusDaemonXPCInterface
    }

    private func handleConnectionInterruption() {
        delegate?.serverTransport(self, didEncounterError: XPCTransportError.daemonConnectionLost)
    }

    private func handleConnectionInvalidation() {
        delegate?.serverTransportDidStopListening(self)
    }
}

// MARK: - AgentXPCHandler

/// SiriusAgentXPCInterface의 실제 구현. NSObject 서브클래스여야 XPC export가 가능하다.
///
/// actor인 XPCServerRoleRootTransport에서 직접 @objc 프로토콜을 구현할 수 없으므로,
/// 이 핸들러 객체가 XPC 호출을 받아서 actor로 전달한다.
private class AgentXPCHandler: NSObject, SiriusAgentXPCInterface {
    private weak var transport: XPCServerRoleRootTransport?

    init(transport: XPCServerRoleRootTransport) {
        self.transport = transport
    }

    func acceptPreAuthenticatedClient(
        _ clientID: NSUUID,
        metadata: SiriusXPCAuthMetadata,
        reply: @escaping (Bool) -> Void
    ) {
        Task {
            guard let transport else {
                reply(false)
                return
            }
            let result = await transport.handleAcceptPreAuthenticatedClient(
                clientID: clientID as UUID,
                metadata: metadata
            )
            reply(result)
        }
    }

    func clientDidOpenRemoteStream(
        _ clientID: NSUUID,
        streamID: NSUUID,
        reply: @escaping (Bool) -> Void
    ) {
        Task {
            guard let transport else {
                reply(false)
                return
            }
            let result = await transport.handleRemoteStreamOpen(
                clientID: clientID as UUID,
                streamID: streamID as UUID
            )
            reply(result)
        }
    }

    func clientDidReceiveStreamData(
        _ clientID: NSUUID,
        streamID: NSUUID,
        data: NSData
    ) {
        Task {
            await transport?.handleStreamData(
                clientID: clientID as UUID,
                streamID: streamID as UUID,
                data: data as Data
            )
        }
    }

    func clientStreamDidClose(_ clientID: NSUUID, streamID: NSUUID) {
        Task {
            await transport?.handleStreamClose(
                clientID: clientID as UUID,
                streamID: streamID as UUID
            )
        }
    }

    func clientStreamDidError(
        _ clientID: NSUUID,
        streamID: NSUUID,
        errorDescription: NSString
    ) {
        Task {
            await transport?.handleStreamError(
                clientID: clientID as UUID,
                streamID: streamID as UUID,
                description: errorDescription as String
            )
        }
    }

    func clientDidDisconnect(_ clientID: NSUUID) {
        Task {
            await transport?.handleClientDisconnect(clientID: clientID as UUID)
        }
    }
}
