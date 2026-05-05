//
//  VirtualTree.swift
//  NoctilucaServer
//
//  Sirius connection / mount session 의 가상 디렉토리 트리. 모든 갱신은
//  ``FSAccessChannel`` / ``NoctilucaClientSession`` 의 push 로만 일어나며,
//  NFS callback 측에서는 read-only.
//
//  각 가상 디렉토리는 mtime 을 보유한다. NFSv4 client (Finder) 가 readdir 결과를
//  cache 하고 디렉토리 mtime 이 변하지 않으면 fresh fetch 를 issue 하지 않으므로,
//  실제로 자식 entries 가 변할 때만 mtime 을 bump 해야 한다 (매 호출마다
//  `now()` 를 주는 hack 도, 부팅시 stamp 로 stable 하게 두는 hack 도 둘 다
//  Finder 의 cache 거동과 정합하지 않아 cycle / stale listing 으로 빠진다).
//

import Foundation

import NanoNFS

/// 1단계 namespace 의 entry. `0001-cheesekun` 형식의 connectionLabel 을 갖는다.
struct VirtualConnectionRecord: Sendable {
    let connectionLabel: String
    var displayName: String
    var mountSessions: [UUID: VirtualMountSessionRecord] = [:]
    /// 자식 mountSession 이 add/remove 될 때마다 갱신.
    var mtime: NFSTime = .now()
}

/// 2단계 namespace 의 entry.
struct VirtualMountSessionRecord: Sendable {
    let id: UUID
    let connectionLabel: String
    var displayName: String
    let grantedAccess: UInt32
    /// VirtualTree 가 보유하는 fallback mtime. mountSession 의 *실 navigator-side
    /// root* mtime 은 NFS server 가 매 getattr 마다 navigator 에 sendStat("/")
    /// 을 호출해 직접 가져오므로, 이 값은 stat 호출이 실패했을 때 fallback.
    var mtime: NFSTime = .now()
}

actor VirtualTree {
    private(set) var connections: [String: VirtualConnectionRecord] = [:]
    /// connectionLabel 안에서 displayName 충돌 시 ` (2)`, ` (3)` suffix 카운터.
    private var displayNameSuffixCounters: [String: [String: Int]] = [:]
    /// root 디렉토리의 mtime. connection add/remove 시 갱신.
    private(set) var rootMtime: NFSTime = .now()

    func addConnection(label: String, displayName: String) {
        if connections[label] != nil {
            connections[label]?.displayName = displayName
            return
        }
        connections[label] = VirtualConnectionRecord(connectionLabel: label, displayName: displayName)
        rootMtime = .now()
    }

    @discardableResult
    func removeConnection(label: String) -> [UUID] {
        guard let record = connections.removeValue(forKey: label) else { return [] }
        displayNameSuffixCounters.removeValue(forKey: label)
        rootMtime = .now()
        return Array(record.mountSessions.keys)
    }

    func addMountSession(connectionLabel: String,
                         mountSessionId: UUID,
                         displayName: String,
                         grantedAccess: UInt32) -> Bool {
        guard var connection = connections[connectionLabel] else { return false }
        let safeDisplayName = sanitizedAndDeduped(displayName, in: connectionLabel)
        let record = VirtualMountSessionRecord(
            id: mountSessionId,
            connectionLabel: connectionLabel,
            displayName: safeDisplayName,
            grantedAccess: grantedAccess
        )
        connection.mountSessions[mountSessionId] = record
        connection.mtime = .now()
        connections[connectionLabel] = connection
        return true
    }

    @discardableResult
    func removeMountSession(_ id: UUID) -> VirtualMountSessionRecord? {
        for (label, var connection) in connections {
            if let removed = connection.mountSessions.removeValue(forKey: id) {
                connection.mtime = .now()
                connections[label] = connection
                return removed
            }
        }
        return nil
    }

    func mountSession(forId id: UUID) -> VirtualMountSessionRecord? {
        for connection in connections.values {
            if let session = connection.mountSessions[id] { return session }
        }
        return nil
    }

    func snapshotConnections() -> [VirtualConnectionRecord] {
        return Array(connections.values).sorted { $0.connectionLabel < $1.connectionLabel }
    }

    /// active connection 이 0개일 때만 root 에 `_README.txt` 를 노출한다.
    func shouldShowReadme() -> Bool {
        return connections.isEmpty
    }

    // MARK: - Mtime queries

    func connectionMtime(label: String) -> NFSTime? {
        return connections[label]?.mtime
    }

    func mountSessionMtime(id: UUID) -> NFSTime? {
        for connection in connections.values {
            if let session = connection.mountSessions[id] { return session.mtime }
        }
        return nil
    }

    // MARK: - Helpers

    private func sanitizedAndDeduped(_ raw: String, in connectionLabel: String) -> String {
        var sanitized = raw
        sanitized = sanitized.replacingOccurrences(of: "/", with: "_")
        sanitized = sanitized.replacingOccurrences(of: "\u{0000}", with: "_")
        if sanitized.isEmpty { sanitized = "(unnamed)" }
        guard let connection = connections[connectionLabel] else { return sanitized }
        let existingNames = Set(connection.mountSessions.values.map { $0.displayName })
        if !existingNames.contains(sanitized) {
            return sanitized
        }
        var counter = displayNameSuffixCounters[connectionLabel]?[sanitized] ?? 1
        while existingNames.contains("\(sanitized) (\(counter + 1))") {
            counter += 1
        }
        let next = "\(sanitized) (\(counter + 1))"
        displayNameSuffixCounters[connectionLabel, default: [:]][sanitized] = counter + 1
        return next
    }
}
