//
//  AgentRegistry.swift
//  noctilucad
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKit

/// Announcement 기반으로 UID → 에이전트 NSXPCConnection 매핑을 관리하는 레지스트리.
///
/// 각 NoctilucaServer 인스턴스는 가동 시 `agentDidStartup(uid:)`으로 자신을 announce하고,
/// 종료 시 `agentWillShutdown()`으로 depart한다.
class AgentRegistry {
    struct AgentEntry {
        let uid: uid_t
        let connection: NSXPCConnection
        let proxy: SiriusAgentXPCInterface

        /// 이 에이전트에 연결된 클라이언트 프록시 목록
        var clientProxies: [UUID: XPCTransportProxy] = [:]
    }

    private var agents: [uid_t: AgentEntry] = [:]

    /// loginwindow 에이전트의 UID (loginwindow 컨텍스트에서 실행되는 NoctilucaServer)
    static let loginWindowUID: uid_t = 0

    // MARK: - Announcement

    /// 에이전트를 등록한다.
    ///
    /// - Parameters:
    ///   - uid: 에이전트의 사용자 UID
    ///   - connection: 에이전트와의 NSXPCConnection
    ///   - proxy: 에이전트의 SiriusAgentXPCInterface 프록시 객체
    func registerAgent(uid: uid_t, connection: NSXPCConnection, proxy: SiriusAgentXPCInterface) {
        agents[uid] = AgentEntry(uid: uid, connection: connection, proxy: proxy)
    }

    /// 에이전트를 해제한다.
    func unregisterAgent(uid: uid_t) {
        agents.removeValue(forKey: uid)
    }

    /// 주어진 NSXPCConnection에 대응하는 에이전트를 찾아 해제한다.
    func unregisterAgent(by connection: NSXPCConnection) {
        guard let entry = agents.first(where: { $0.value.connection === connection }) else {
            return
        }
        agents.removeValue(forKey: entry.key)
    }

    // MARK: - Lookup

    /// 주어진 UID에 대응하는 에이전트를 찾는다.
    func agent(for uid: uid_t) -> AgentEntry? {
        agents[uid]
    }

    /// 주어진 UID에 대응하는 에이전트가 없으면 loginwindow 에이전트로 폴백한다.
    func agentWithFallback(for uid: uid_t) -> AgentEntry? {
        if let agent = agents[uid] {
            return agent
        }
        return agents[Self.loginWindowUID]
    }

    /// 현재 등록된 에이전트 수.
    var count: Int { agents.count }

    /// 현재 등록된 모든 에이전트의 UID 목록.
    var registeredUIDs: [uid_t] { Array(agents.keys) }

    // MARK: - Client Proxy Management

    /// 주어진 UID의 에이전트에 클라이언트 프록시를 등록한다.
    func registerClientProxy(_ proxy: XPCTransportProxy, for uid: uid_t) {
        agents[uid]?.clientProxies[proxy.clientID] = proxy
    }

    /// 주어진 UID의 에이전트에서 클라이언트 프록시를 해제한다.
    func unregisterClientProxy(clientID: UUID, for uid: uid_t) {
        agents[uid]?.clientProxies.removeValue(forKey: clientID)
    }

    /// 등록된 모든 에이전트에서 주어진 clientID의 프록시를 찾는다.
    func findClientProxy(clientID: UUID) -> (uid: uid_t, proxy: XPCTransportProxy)? {
        for (uid, entry) in agents {
            if let proxy = entry.clientProxies[clientID] {
                return (uid, proxy)
            }
        }
        return nil
    }
}
