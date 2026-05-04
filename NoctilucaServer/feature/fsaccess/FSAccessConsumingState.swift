//
//  FSAccessConsumingState.swift
//  NoctilucaServer
//
//  단일 fsaccess control channel 안의 consuming 측 상태 (List 응답 entries,
//  활성 mount session 들, requestId 발급기). 서버는 navigator 별로
//  이 state actor 를 하나씩 갖는다.
//

import Foundation

import SiriusKit

/// 한 mount session 의 host 측 상태 스냅샷.
struct FSAccessMountSessionRecord: Sendable {
    /// `FileSystemMountResponse.sessionId`.
    let id: UUID
    /// 상위 connection 의 1단계 namespace label (e.g. `0001-cheesekun`).
    let connectionLabel: String
    /// 마운트한 entry — 가상 트리의 2단계 displayName 결정에 사용.
    let entry: FileSystemEntry
    /// 응답으로 받은 grantedAccess.
    let grantedAccess: AccessMode
}

actor FSAccessConsumingState {
    /// 마지막 List 응답으로 받은 entries (정책 평가에 사용).
    private(set) var entries: [FileSystemEntry] = []
    /// sessionId → record. mount channel 자체는 ``FSAccessRequestRouter`` 가 별도 보유.
    private(set) var mountSessions: [UUID: FSAccessMountSessionRecord] = [:]
    /// 현 control channel 의 1단계 connection label. addConnection 호출 시 결정.
    private(set) var connectionLabel: String?

    private var nextRequestIdValue: UInt64 = 1

    func issueRequestId() -> UInt64 {
        let value = nextRequestIdValue
        // wrapping add — UInt64 overflow 까지 가서 0 으로 wrap 되면 1 부터 다시.
        nextRequestIdValue = nextRequestIdValue &+ 1
        if nextRequestIdValue == 0 { nextRequestIdValue = 1 }
        return value
    }

    func setConnectionLabel(_ label: String?) {
        connectionLabel = label
    }

    func setEntries(_ newEntries: [FileSystemEntry]) {
        entries = newEntries
    }

    func addMountSession(_ record: FSAccessMountSessionRecord) {
        mountSessions[record.id] = record
    }

    @discardableResult
    func removeMountSession(_ id: UUID) -> FSAccessMountSessionRecord? {
        return mountSessions.removeValue(forKey: id)
    }

    func mountSession(forId id: UUID) -> FSAccessMountSessionRecord? {
        return mountSessions[id]
    }

    func mountSessionsSnapshot() -> [FSAccessMountSessionRecord] {
        return Array(mountSessions.values)
    }
}
