//
//  DaemonXPCService.swift
//  noctilucad
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKit
import SiriusKitCore

// FIXME: @cheesekun - Mach 서비스 이름은 launchd plist와 일치해야 한다.
let kNoctilucaDaemonMachServiceName = "pl.unstabler.noctiluca.server.noctilucad"

/// noctilucad의 XPC 서비스.
///
/// NSXPCListener를 통해 NoctilucaServer(Agent) 인스턴스의 연결을 수락하고,
/// SiriusDaemonXPCInterface를 구현하여 에이전트의 요청을 처리한다.
class DaemonXPCService: NSObject {
    let listener: NSXPCListener
    let agentRegistry: AgentRegistry

    init(agentRegistry: AgentRegistry) {
        self.listener = NSXPCListener(machServiceName: kNoctilucaDaemonMachServiceName)
        self.agentRegistry = agentRegistry
        super.init()

        self.listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func stop() {
        listener.suspend()
    }
}

// MARK: - NSXPCListenerDelegate

extension DaemonXPCService: NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // 양방향 인터페이스 설정
        newConnection.exportedInterface = createSiriusDaemonXPCInterface()
        newConnection.remoteObjectInterface = createSiriusAgentXPCInterface()

        let handler = DaemonXPCHandler(
            connection: newConnection,
            agentRegistry: agentRegistry
        )
        newConnection.exportedObject = handler

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let connection = newConnection else { return }
            self.agentRegistry.unregisterAgent(by: connection)
        }

        newConnection.resume()
        return true
    }
}

// MARK: - DaemonXPCHandler

/// SiriusDaemonXPCInterface의 실제 구현. 에이전트의 XPC 호출을 처리한다.
private class DaemonXPCHandler: NSObject, SiriusDaemonXPCInterface {
    private let connection: NSXPCConnection
    private let agentRegistry: AgentRegistry

    /// 이 핸들러가 관리하는 에이전트의 UID. agentDidStartup 후에 설정된다.
    private var agentUID: uid_t?

    init(connection: NSXPCConnection, agentRegistry: AgentRegistry) {
        self.connection = connection
        self.agentRegistry = agentRegistry
    }

    // MARK: - Announcement

    func agentDidStartup(uid: uid_t, reply: @escaping (Bool) -> Void) {
        self.agentUID = uid

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            // 에이전트 프록시 에러 처리
            _ = error
        } as! SiriusAgentXPCInterface

        agentRegistry.registerAgent(uid: uid, connection: connection, proxy: proxy)
        reply(true)
    }

    func agentWillShutdown(reply: @escaping () -> Void) {
        if let uid = agentUID {
            agentRegistry.unregisterAgent(uid: uid)
        }
        reply()
    }

    // MARK: - Stream Operations

    func openStream(
        clientID: NSUUID,
        streamID: NSUUID,
        reply: @escaping (Bool) -> Void
    ) {
        let clientUUID = clientID as UUID

        guard let (_, proxy) = agentRegistry.findClientProxy(clientID: clientUUID) else {
            reply(false)
            return
        }

        Task {
            let success = await proxy.handleAgentOpenStream(streamID: streamID as UUID)
            reply(success)
        }
    }

    func writeStreamData(
        clientID: NSUUID,
        streamID: NSUUID,
        data: NSData,
        reply: @escaping (UInt32, NSString?) -> Void
    ) {
        let clientUUID = clientID as UUID
        let streamUUID = streamID as UUID

        guard let (_, proxy) = agentRegistry.findClientProxy(clientID: clientUUID) else {
            reply(0, "Client not found" as NSString)
            return
        }

        Task {
            let (bytesWritten, error) = await proxy.handleAgentWriteData(
                streamID: streamUUID,
                data: data as Data
            )
            reply(bytesWritten, error.map { $0 as NSString })
        }
    }

    func closeStream(
        clientID: NSUUID,
        streamID: NSUUID,
        reply: @escaping (Bool) -> Void
    ) {
        let clientUUID = clientID as UUID
        let streamUUID = streamID as UUID

        guard let (_, proxy) = agentRegistry.findClientProxy(clientID: clientUUID) else {
            reply(false)
            return
        }

        Task {
            let success = await proxy.handleAgentCloseStream(streamID: streamUUID)
            reply(success)
        }
    }

    func setStreamServiceClass(
        clientID: NSUUID,
        streamID: NSUUID,
        rawValue: UInt8,
        reply: @escaping (Bool) -> Void
    ) {
        let clientUUID = clientID as UUID
        let streamUUID = streamID as UUID

        guard let (_, proxy) = agentRegistry.findClientProxy(clientID: clientUUID) else {
            reply(false)
            return
        }

        Task {
            let success = await proxy.handleAgentSetServiceClass(streamID: streamUUID, rawValue: rawValue)
            reply(success)
        }
    }

    func disconnectClient(
        _ clientID: NSUUID,
        reply: @escaping (Bool) -> Void
    ) {
        let clientUUID = clientID as UUID

        guard let (uid, proxy) = agentRegistry.findClientProxy(clientID: clientUUID) else {
            reply(false)
            return
        }

        Task {
            await proxy.handleAgentDisconnect()
            agentRegistry.unregisterClientProxy(clientID: clientUUID, for: uid)
            reply(true)
        }
    }
}
