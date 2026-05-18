//
//  NoctilucaServerExtensionV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation

/// 서버 확장 플러그인이 이벤트를 관찰하기 위한 컨텍스트
public protocol NoctilucaServerExtensionContext: AnyObject, Sendable {
    func subscribe(to eventType: NoctilucaServerEventTypeV1) async
    func unsubscribe(from eventType: NoctilucaServerEventTypeV1) async
    
    /// 이벤트에 답장합니다.
    /// - 이벤트마다 desire 하는 타입이 다를 수 있습니다. 타입이 다르면 오류를 던집니다.
    /// - 여러번 답장하면 오류 던집니다.
    func reply(to token: NoctilucaServerEventToken, intValue: Int64) throws
    /// 이벤트에 답장합니다.
    /// - 이벤트마다 desire 하는 타입이 다를 수 있습니다. 타입이 다르면 오류를 던집니다.
    /// - 여러번 답장하면 오류 던집니다.
    func reply(to token: NoctilucaServerEventToken, stringValue: String) throws
    /// 이벤트에 답장합니다.
    /// - 이벤트마다 desire 하는 타입이 다를 수 있습니다. 타입이 다르면 오류를 던집니다.
    /// - 여러번 답장하면 오류 던집니다.
    func reply(to token: NoctilucaServerEventToken, data: Data) throws
    
    /// 이벤트를 인터럽트합니다. (실패할 수도 있음 ㅎ)
    func interrupt(which token: NoctilucaServerEventToken) throws
}

/// 서버 확장 플러그인 V1
/// 서버 이벤트를 관찰하고 반응하는 저레벨 확장 (예: fail2ban)
public protocol NoctilucaServerExtensionV1: AnyObject, Sendable {
    static var id: String { get }

    init()

    func start(with context: NoctilucaServerExtensionContext) async throws
    func onEvent(context: NoctilucaServerExtensionContext, event: NoctilucaServerEventV1) async
    func stop() async
}
