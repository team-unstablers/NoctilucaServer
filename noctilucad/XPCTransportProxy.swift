//
//  XPCTransportProxy.swift
//  noctilucad
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKit
import SiriusKitCore

/// 실제 QUIC ServerRoleClientTransport를 XPC를 통해 에이전트로 프록시하는 클래스.
///
/// noctilucad가 MainChannel 인증을 완료한 후, 이 프록시가 해당 클라이언트의
/// 모든 스트림 이벤트를 에이전트로 중계한다.
class XPCTransportProxy {
    let clientID: UUID
    let transport: any ServerRoleClientTransport
    let agentProxy: SiriusAgentXPCInterface

    /// 연결이 종료되었을 때 호출되는 콜백. AgentRegistry에서 프록시를 제거하는 데 사용한다.
    var onClose: ((UUID) -> Void)?

    private var streamProxies: [StreamIdentifier: XPCStreamProxy] = [:]

    init(
        clientID: UUID,
        transport: any ServerRoleClientTransport,
        agentProxy: SiriusAgentXPCInterface
    ) {
        self.clientID = clientID
        self.transport = transport
        self.agentProxy = agentProxy
    }

    /// MainChannel 인증 완료 후, MainChannel 스트림의 이벤트 포워딩을 시작하고
    /// 트랜스포트의 delegate를 내부 핸들러로 설정하여 새 스트림을 감지한다.
    ///
    /// - Parameter mainChannelStream: 이미 열려 있는 MainChannel 스트림
    func startProxying(mainChannelStream: SiriusKit.Stream) {
        // MainChannel 스트림 프록시 설정
        let mainProxy = XPCStreamProxy(
            streamID: mainChannelStream.id,
            stream: mainChannelStream,
            clientID: clientID,
            agentProxy: agentProxy
        )
        streamProxies[mainChannelStream.id] = mainProxy

        // 에이전트에 MainChannel 스트림 열림을 알린다.
        // 에이전트의 XPCServerRoleClientTransport가 이 알림을 받아야
        // ClientSession이 MainChannel을 생성할 수 있다.
        agentProxy.clientDidOpenRemoteStream(
            clientID as NSUUID,
            streamID: mainChannelStream.id as NSUUID
        ) { accepted in
            guard accepted else { return }
            // 에이전트가 스트림을 수락한 후 데이터 포워딩 시작
            mainProxy.startForwarding()
        }
    }

    /// 에이전트에서 새 스트림 열기 요청을 받았을 때 호출한다.
    func handleAgentOpenStream(streamID: UUID) async -> Bool {
        let result = await transport.openStream()

        switch result {
        case .success(let stream):
            let proxy = XPCStreamProxy(
                streamID: streamID,
                stream: stream,
                clientID: clientID,
                agentProxy: agentProxy
            )
            streamProxies[streamID] = proxy
            proxy.startForwarding()
            return true

        case .failure:
            return false
        }
    }

    /// 에이전트에서 스트림 데이터 쓰기 요청을 받았을 때 호출한다.
    func handleAgentWriteData(streamID: UUID, data: Data) async -> (UInt32, String?) {
        guard let proxy = streamProxies[streamID] else {
            return (0, "Stream not found: \(streamID)")
        }
        return await proxy.write(data)
    }

    /// 에이전트에서 스트림 닫기 요청을 받았을 때 호출한다.
    func handleAgentCloseStream(streamID: UUID) async -> Bool {
        guard let proxy = streamProxies[streamID] else { return false }
        await proxy.close()
        streamProxies.removeValue(forKey: streamID)
        return true
    }

    /// 에이전트에서 스트림 서비스 클래스 설정 요청을 받았을 때 호출한다.
    func handleAgentSetServiceClass(streamID: UUID, rawValue: UInt8) async -> Bool {
        guard let proxy = streamProxies[streamID] else { return false }
        await proxy.setServiceClass(rawValue)
        return true
    }

    /// 에이전트에서 클라이언트 연결 끊기 요청을 받았을 때 호출한다.
    func handleAgentDisconnect() async {
        cleanupStreamProxies()
        await transport.disconnect()
        onClose?(clientID)
    }

    /// 클라이언트 측(QUIC)에서 연결이 종료되었을 때 호출한다.
    func handleTransportClose() {
        cleanupStreamProxies()
        agentProxy.clientDidDisconnect(clientID as NSUUID)
        onClose?(clientID)
    }

    private func cleanupStreamProxies() {
        let snapshot = Array(streamProxies.values)
        streamProxies.removeAll()

        for proxy in snapshot {
            proxy.stopForwarding()
        }
    }
}

// MARK: - ServerRoleClientTransportDelegate

extension XPCTransportProxy: ServerRoleClientTransportDelegate {
    func clientTransportDidOpenRemoteStream(
        _ transport: any ServerRoleClientTransport,
        stream: SiriusKitCore.Stream
    ) async throws {
        let streamID = stream.id

        let proxy = XPCStreamProxy(
            streamID: streamID,
            stream: stream,
            clientID: clientID,
            agentProxy: agentProxy
        )
        streamProxies[streamID] = proxy
        proxy.startForwarding()

        // 에이전트에 원격 스트림 열림 알림
        agentProxy.clientDidOpenRemoteStream(
            clientID as NSUUID,
            streamID: streamID as NSUUID
        ) { _ in }
    }

    func clientTransportDidCloseStream(
        _ transport: any ServerRoleClientTransport,
        stream: SiriusKitCore.Stream
    ) async {
        let streamID = stream.id

        if let proxy = streamProxies[streamID] {
            proxy.stopForwarding()
            streamProxies.removeValue(forKey: streamID)
        }

        agentProxy.clientStreamDidClose(
            clientID as NSUUID,
            streamID: streamID as NSUUID
        )
    }

    func clientTransportDidClose(_ transport: any ServerRoleClientTransport) async {
        handleTransportClose()
    }

    func clientTransport(
        _ transport: any ServerRoleClientTransport,
        didEncounterError error: any Error
    ) async {
        // 에러 발생 시 에이전트에 알리고 정리
        handleTransportClose()
    }
}
