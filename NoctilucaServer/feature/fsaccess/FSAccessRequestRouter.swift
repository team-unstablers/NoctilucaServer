//
//  FSAccessRequestRouter.swift
//  NoctilucaServer
//
//  데몬 → 호스트 reverse-XPC 콜백이 도달하면 어느 ``FSAccessMountChannel`` 로
//  forward 할지 결정하는 process-wide 라우터. mountSessionId (UUID) 를 키로
//  활성 mount channel 을 보유한다.
//

import Foundation

actor FSAccessRequestRouter {
    static let shared = FSAccessRequestRouter()

    private var channels: [UUID: FSAccessMountChannel] = [:]

    func register(_ channel: FSAccessMountChannel, for sessionId: UUID) {
        channels[sessionId] = channel
    }

    @discardableResult
    func unregister(sessionId: UUID) -> FSAccessMountChannel? {
        return channels.removeValue(forKey: sessionId)
    }

    func channel(for sessionId: UUID) -> FSAccessMountChannel? {
        return channels[sessionId]
    }

    func snapshotActiveSessions() -> [UUID] {
        return Array(channels.keys)
    }
}
