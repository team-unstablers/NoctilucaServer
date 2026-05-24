//
//  NoctilucaServerEventV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation

public typealias NoctilucaServerEventToken = UUID

// TODO: XPC 통해서 오갈 수 있어야 함
public protocol NoctilucaServerEventV1: Sendable {
    var eventType: NoctilucaServerEventTypeV1 { get }
}

public protocol NoctilucaServerInteractiveEventV1: NoctilucaServerEventV1 {
    /// 이벤트에 응답하거나 인터럽트 등을 걸어야 하는 경우 사용됩니다.
    var token: NoctilucaServerEventToken { get }
}

/*
public enum NoctilucaServerAuthChallengeEventReplyV1: Int64, Sendable {
    case allow = 1
    case deny = 2
}

public struct NoctilucaServerAuthChallengeEventV1: NoctilucaServerInteractiveEventV1 {
    // 코드 그지같아도 그냥 컨셉 표현한 거니까 너무 뭐라 그러지 말아요 ㅠ
    let remoteAddress: String
    let clientInfo: String // FIXME
}

public extension NoctilucaServerAuthChallengeEventV1 {
    func reply(_ context: any NoctilucaServerExtensionContext, decision: NoctilucaServerAuthChallengeEventReplyV1) {
        context.reply(to: token, intValue: decision.rawValue)
    }
}
*/
