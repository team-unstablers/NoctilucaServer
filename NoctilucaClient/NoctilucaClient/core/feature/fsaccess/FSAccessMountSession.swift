//
//  FSAccessMountSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import Foundation

import SiriusKitClient

/// 활성 mount 세션 한 건의 상태.
///
/// `FSAccessChannel` 이 생성하고 `RemoteSession` 에 등록한다.
/// 대응하는 `FSAccessMountChannel` 이 생기면 `mountChannel` 이 채워진다.
final class FSAccessMountSession: @unchecked Sendable {
    let id: UUID
    let entryId: UUID
    let entryName: String
    let rootURL: URL
    let grantedAccess: AccessMode

    private let lock = NSLock()
    private var _mountChannel: FSAccessMountChannel?

    init(id: UUID, entryId: UUID, entryName: String, rootURL: URL, grantedAccess: AccessMode) {
        self.id = id
        self.entryId = entryId
        self.entryName = entryName
        self.rootURL = rootURL
        self.grantedAccess = grantedAccess
    }

    var mountChannel: FSAccessMountChannel? {
        lock.lock()
        defer { lock.unlock() }
        return _mountChannel
    }

    func setMountChannel(_ channel: FSAccessMountChannel?) {
        lock.lock()
        defer { lock.unlock() }
        _mountChannel = channel
    }
}

/// Stream R/W 라우팅을 위한 보조 모델.
/// 클라가 sender(stream-read) 또는 receiver(stream-write) 가 될 수 있다.
final class FSAccessStreamRoute: @unchecked Sendable {
    enum Kind {
        /// 클라가 sender. local TransferChannel 을 직접 연다.
        case read(handleId: UInt64, offset: UInt64, length: UInt64)
        /// 클라가 receiver. 서버가 open 한 incoming TransferChannel 을 매칭으로 받는다.
        case write(handleId: UInt64, offset: UInt64, length: UInt64)
    }

    let transferId: UUID
    let mountSessionId: UUID
    let kind: Kind

    init(transferId: UUID, mountSessionId: UUID, kind: Kind) {
        self.transferId = transferId
        self.mountSessionId = mountSessionId
        self.kind = kind
    }
}
