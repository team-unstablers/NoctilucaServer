//
//  NoctilucaClientManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import Combine

import SiriusKitClient

@MainActor
class NoctilucaClientManager: ObservableObject {
    nonisolated public static let shared = NoctilucaClientManager()
    
    private let logger = NoctilucaLogger(category: "NoctilucaClientManager")
    
    @Published
    private(set) public var clients: [UUID: NoctilucaClient] = [:]
    
    nonisolated private init() {
        
    }
    
    public func createClient(
        to endpoint: SREndpoint,
        settings: SessionSettings?,
    ) async throws -> NoctilucaClient {
        let featureProvider = NoctilucaFeatureProvider()
        let siriusClientResult = SiriusClientBuilder()
            .useTransportProtocol(.quic(endpoint: endpoint))
            .useFeatureProvider(featureProvider)
            .useServerIdentityValidationPolicy(.systemOnly) // 유저랜드 핸들러는 나중에 세팅할 것임
            .build()

        let session = try siriusClientResult.get()
        let client = NoctilucaClient(session)

        client.noctilucaFeatureProvider = featureProvider
        client.sessionSettings = settings
        // FeatureProvider 가 NoctilucaClient 에 도달할 수 있도록 weak ref 주입.
        // (FSAccessChannel / TransferChannel 라우팅에서 sessionSettings / RemoteSession 접근에 사용)
        await featureProvider.setNoctilucaClient(client)
        
        guard !clients.keys.contains(client.id) else {
            self.logger.warning("Client with ID \(client.id.uuidString) already exists. Skipping adding new client.")
            
            return client
        }
        
        clients[client.id] = client
        
        return client
    }
    
    public func killClient(id: UUID) async {
        guard let client = clients[id] else {
            self.logger.warning("No client found with ID \(id.uuidString). Cannot kill non-existing client.")
            return
        }
        
        await client.close()
        clients[id] = nil
    }
    
    public func killClient(client: NoctilucaClient) async {
        await self.killClient(id: client.id)
    }
    
    public func detachClient(id: UUID) {
        clients[id] = nil
    }
    
    public func detachClient(client: NoctilucaClient) {
        self.detachClient(id: client.id)
    }

    /// 활성 클라이언트가 있는지 여부를 반환한다.
    public var hasActiveClients: Bool {
        clients.values.contains { $0.phase != .closed }
    }

    /// 모든 활성 클라이언트를 종료하고 목록을 비운다.
    /// 앱 종료 전 호출하여 모든 세션이 정상 종료되도록 보장한다.
    public func shutdownAllClients() async {
        let activeClients = clients.values.filter { $0.phase != .closed }

        await withTaskGroup(of: Void.self) { group in
            for client in activeClients {
                group.addTask {
                    await client.close()
                }
            }
        }

        clients.removeAll()
    }
}


