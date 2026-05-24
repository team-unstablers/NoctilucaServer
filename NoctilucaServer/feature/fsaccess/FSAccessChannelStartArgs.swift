//
//  FSAccessChannelStartArgs.swift
//  NoctilucaServer
//
//  fsaccess_mount channel 의 ChannelStartRequest.args 직렬화 헬퍼.
//

import Foundation

/// `fsaccess_mount` channel 은 `args[0]` 에 mount session 의 SRUUID 문자열을
/// 담아서 연다 (mdproto §IMPLEMENTATION NOTES — channel arguments).
enum FSAccessMountChannelArgs {
    static func encode(sessionId: UUID) -> [String] {
        return [sessionId.uuidString]
    }

    static func parse(_ args: [String]) -> UUID? {
        guard let first = args.first else { return nil }
        return UUID(uuidString: first)
    }
}
