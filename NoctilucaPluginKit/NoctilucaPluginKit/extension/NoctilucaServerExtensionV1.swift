//
//  NoctilucaServerExtensionV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation

public enum NOCAddressFamily {
    case IPv4(UInt32)
    case IPv6(high: UInt64, low: UInt64, scopeId: UInt32 = 0)
    
    case other(Data)
}

public struct NOCRemoteAddress {
    public let address: NOCAddressFamily
    public let port: UInt16
}

public struct NOCClientInfo {
    let agentName: String
}

public struct NOCClientConnection {
    let remoteAddress: NOCRemoteAddress
    let clientInfo: NOCClientInfo
}

public enum NOCConnectionDecision {
    case accept
    case block
}

/// 서버 확장 플러그인이 이벤트를 관찰하기 위한 컨텍스트
public protocol NoctilucaServerExtensionContext: AnyObject, Sendable {
    func subscribe(to eventType: NoctilucaServerEventTypeV1) async
    func unsubscribe(from eventType: NoctilucaServerEventTypeV1) async
}

/// 서버 확장 플러그인 V1
/// 서버 이벤트를 관찰하고 반응하는 저레벨 확장 (예: fail2ban)
public protocol NoctilucaServerExtensionV1: AnyObject, Sendable {
    static var id: String { get }

    init()
    
    func start(with context: NoctilucaServerExtensionContext) async throws
    func stop() async
    
    func onEvent(context: NoctilucaServerExtensionContext, event: NoctilucaServerEventV1) async
    
    func onNewConnection(context: NoctilucaServerExtensionContext, connection: NOCClientConnection) async -> NOCConnectionDecision
    func onAuthSucceed(context: NoctilucaServerExtensionContext, connection: NOCClientConnection) async
    func onAuthFailed(context: NoctilucaServerExtensionContext, connection: NOCClientConnection) async
}


public extension NoctilucaServerExtensionV1 {
    func onEvent(context: NoctilucaServerExtensionContext, event: NoctilucaServerEventV1) async {
        // default stub
    }
    
    func onNewConnection(context: NoctilucaServerExtensionContext, connection: NOCClientConnection) async -> NOCConnectionDecision {
        return .accept
    }
    
    func onAuthSucceed(context: NoctilucaServerExtensionContext, connection: NOCClientConnection) async {
        // default stub
    }
    func onAuthFailed(context: NoctilucaServerExtensionContext, connection: NOCClientConnection) async {
        // default stub
    }
}
