//
//  HandleTable.swift
//  nocfsaccessd
//
//  NFSv4 file handle ↔ daemon-internal entry id ↔ host-side fsaccess_mount
//  handleId 매핑. 데몬은 NFSFileHandle 의 opaque blob 안에 자체 식별자를 인코딩
//  해서 NFS client 에 보내고, 클라이언트가 같은 blob 을 돌려 보내면 매핑에서
//  실 식별자를 복원한다.
//
//  본 stage 의 구현은 *최소한* 의 in-memory 매핑이며, 실제 NFS 콜백 dispatch
//  로직 (host XPC 위임 등) 은 NoctilucaNFSServer 가 본 actor 를 통해 사용한다.
//

import Foundation

/// NFSFileHandle 의 opaque blob 안에 인코딩되는 daemon-internal 식별자 종류.
enum HandleEntryKind: UInt8, Sendable {
    case root = 0
    case readme = 1
    case connection = 2
    case mountSession = 3
    /// mount session 안의 hostHandleId 가 묶인 실 파일/디렉토리 entry.
    case hostFile = 4
}

struct HandleEntry: Sendable {
    let kind: HandleEntryKind
    /// kind 가 `.connection` / `.mountSession` / `.hostFile` 일 때만 의미 있음.
    let connectionLabel: String?
    let mountSessionId: UUID?
    /// kind 가 `.hostFile` 일 때만 의미 있음 (host 측 handleId).
    let hostHandleId: UInt64?
    /// `.hostFile` 일 때, host 측 fsaccess_mount root 기준의 normalized path.
    let path: String?
}

actor HandleTable {
    /// daemon-internal opaque entry id (UInt64) → entry.
    private var entries: [UInt64: HandleEntry] = [:]
    private var nextId: UInt64 = 16  // 0..15 reserved

    static let rootEntryId: UInt64 = 1
    static let readmeEntryId: UInt64 = 2

    init() {
        entries[Self.rootEntryId] = HandleEntry(
            kind: .root, connectionLabel: nil, mountSessionId: nil, hostHandleId: nil, path: nil
        )
        entries[Self.readmeEntryId] = HandleEntry(
            kind: .readme, connectionLabel: nil, mountSessionId: nil, hostHandleId: nil, path: nil
        )
    }

    /// 새 id 를 발급해서 entry 를 등록.
    func issue(_ entry: HandleEntry) -> UInt64 {
        let id = nextId
        nextId &+= 1
        if nextId == 0 { nextId = 16 }
        entries[id] = entry
        return id
    }

    func get(_ id: UInt64) -> HandleEntry? {
        return entries[id]
    }

    /// `mountSessionId` 에 속한 모든 entry 를 invalidate. mount session 제거 시 호출.
    @discardableResult
    func invalidateAll(mountSession: UUID) -> Int {
        var removed = 0
        for (id, entry) in entries where entry.mountSessionId == mountSession {
            entries.removeValue(forKey: id)
            removed += 1
        }
        return removed
    }

    /// `connectionLabel` 에 속한 모든 entry 를 invalidate.
    @discardableResult
    func invalidateAll(connection label: String) -> Int {
        var removed = 0
        for (id, entry) in entries where entry.connectionLabel == label {
            entries.removeValue(forKey: id)
            removed += 1
        }
        return removed
    }

    // MARK: - NFSFileHandle bytes <-> entry id

    /// daemon-internal entry id 를 NFSFileHandle.bytes 의 8-byte BE 로 인코딩.
    static func encode(_ id: UInt64) -> Data {
        var be = id.bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }

    /// NFSFileHandle.bytes 가 8-byte BE 면 daemon-internal entry id 로 디코딩.
    static func decode(_ data: Data) -> UInt64? {
        guard data.count == 8 else { return nil }
        var be: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &be) { buffer in
            data.copyBytes(to: buffer)
        }
        return UInt64(bigEndian: be)
    }
}
