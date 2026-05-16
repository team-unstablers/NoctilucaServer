//
//  NoctilucaServerExtensionV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/9/25.
//

/// 서버 확장 플러그인이 이벤트를 관찰하기 위한 컨텍스트
public protocol NoctilucaServerExtensionContext: AnyObject, Sendable {
    func subscribe(to eventType: String) async
    func unsubscribe(from eventType: String) async
}

/// 서버 확장 플러그인 V1
/// 서버 이벤트를 관찰하고 반응하는 저레벨 확장 (예: fail2ban)
public protocol NoctilucaServerExtensionV1: AnyObject, Sendable {
    static var id: String { get }

    init()

    func start(with context: NoctilucaServerExtensionContext) async throws
    func onEvent(type eventType: String, payload: any Sendable) async
    func stop() async
}
