//
//  HandleTable.swift
//  NoctilucaServer
//
//  NFSv4 file handle ↔ host-side entry id ↔ navigator-side fsaccess_mount
//  handleId 매핑.
//
//  같은 가상 entry (connection / mount session / host file path) 에 대해서는
//  *항상 같은 entry id* 를 재사용한다. NFSv4 client 가 fh 를 cache 하므로
//  매번 다른 fh 를 주면 client 가 ESTALE 로 환원해 file 접근이 fail 한다.
//

import Foundation

enum HandleEntryKind: UInt8, Sendable {
    case root = 0
    case readme = 1
    case connection = 2
    case mountSession = 3
    /// mount session 안의 navigator-side fsaccess_mount entry.
    case hostFile = 4
}

struct HandleEntry: Sendable {
    let kind: HandleEntryKind
    let connectionLabel: String?
    let mountSessionId: UUID?
    let hostFileId: UInt64?
}

actor HandleTable {
    private var entries: [UInt64: HandleEntry] = [:]
    /// 가상 entry 의 stable lookup key → entryId. 같은 (connection / mount
    /// session / hostFile path) 는 같은 entryId 를 재사용한다.
    private var byKey: [String: UInt64] = [:]
    private var nextId: UInt64 = 16  // 0..15 reserved

    static let rootEntryId: UInt64 = 1
    static let readmeEntryId: UInt64 = 2

    init() {
        entries[Self.rootEntryId] = HandleEntry(
            kind: .root, connectionLabel: nil, mountSessionId: nil, hostFileId: nil
        )
        entries[Self.readmeEntryId] = HandleEntry(
            kind: .readme, connectionLabel: nil, mountSessionId: nil, hostFileId: nil
        )
    }

    // MARK: - Stable id issuance

    /// `key` 로 등록된 entry id 가 있으면 그걸 리턴. 없으면 새 id 를 발급해 등록.
    func issueIfAbsent(_ entry: HandleEntry, key: String) -> UInt64 {
        if let existing = byKey[key] { return existing }
        let id = nextId
        nextId &+= 1
        if nextId == 0 { nextId = 16 }
        entries[id] = entry
        byKey[key] = id
        return id
    }

    static func keyForConnection(_ label: String) -> String {
        return "conn:\(label)"
    }

    static func keyForMountSession(_ id: UUID) -> String {
        return "mount:\(id.uuidString)"
    }

    static func keyForHostFile(mountSessionId: UUID, path: String) -> String {
        return "host:\(mountSessionId.uuidString):\(path)"
    }

    // MARK: - Lookup

    func get(_ id: UInt64) -> HandleEntry? {
        return entries[id]
    }

    @discardableResult
    func invalidateAll(mountSession: UUID) -> Int {
        var removed = 0
        for (id, entry) in entries where entry.mountSessionId == mountSession {
            entries.removeValue(forKey: id)
            removed += 1
        }
        // byKey 에서도 cascade 정리.
        byKey = byKey.filter { entry in entries[entry.value] != nil }
        return removed
    }

    @discardableResult
    func invalidateAll(connection label: String) -> Int {
        var removed = 0
        for (id, entry) in entries where entry.connectionLabel == label {
            entries.removeValue(forKey: id)
            removed += 1
        }
        byKey = byKey.filter { entry in entries[entry.value] != nil }
        return removed
    }

    // MARK: - NFSFileHandle codec

    static func encode(_ id: UInt64) -> Data {
        var be = id.bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }

    static func decode(_ data: Data) -> UInt64? {
        guard data.count == 8 else { return nil }
        var be: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &be) { buffer in
            data.copyBytes(to: buffer)
        }
        return UInt64(bigEndian: be)
    }
}
