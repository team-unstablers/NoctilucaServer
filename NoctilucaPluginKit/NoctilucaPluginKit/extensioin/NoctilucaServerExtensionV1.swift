//
//  RenameMePluginV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/9/25.
//

/*
public struct ClientRemoteEndpoint {
    public let ipAddress: String
    public let port: UInt16
}

public enum NoctilucaServerEventType {
    case serverAppStarted
    case serverTransportStarted
    case clientConnectionEstablished
}

public enum NoctilucaServerEvent {
    case serverAppStarted
    case serverTransportStarted
    case clientConnectionEstablished(clientInfo: ClientRemoteEndpoint, client: ClientConnection)
}

public protocol RenameMePluginV1ServerContext: AnyObject {
    func startObserve(for event: NoctilucaServerEventType) async
}

/// 이름 뭘로 지어야 할지 모르겠다
public protocol RenameMePluginV1: AnyObject {
    
    func start(with context: RenameMePluginV1ServerContext) async throws
    
    func onEvent(_ event: NoctilucaServerEvent) async
}


// ...

class Fail2BanPlugin: RenameMePluginV1 {
    func start(with context: any RenameMePluginV1ServerContext) async throws {
        await context.startObserve(for: .clientConnectionEstablished)
    }
    
    func isBanned(ipAddress: String) async -> Bool {
        // ...
        return false
    }
    
    func onEvent(_ event: NoctilucaServerEvent) async {
        guard case .clientConnectionEstablished(let clientInfo, let client) = event else {
            return
        }
        
        if await isBanned(ipAddress: clientInfo.ipAddress) {
            await client.disconnect()
        }
    }
    
}

*/
