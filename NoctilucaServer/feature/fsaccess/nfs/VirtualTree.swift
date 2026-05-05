//
//  VirtualTree.swift
//  NoctilucaServer
//
//  Sirius connection / mount session 의 가상 디렉토리 트리. 모든 갱신은
//  ``FSAccessChannel`` / ``NoctilucaClientSession`` 의 push 로만 일어나며,
//  NFS callback 측에서는 read-only.
//

import Foundation

/// 1단계 namespace 의 entry. `0001-cheesekun` 형식의 connectionLabel 을 갖는다.
struct VirtualConnectionRecord: Sendable {
    let connectionLabel: String
    var displayName: String
    var mountSessions: [UUID: VirtualMountSessionRecord] = [:]
}

/// 2단계 namespace 의 entry.
struct VirtualMountSessionRecord: Sendable {
    let id: UUID
    let connectionLabel: String
    var displayName: String
    let grantedAccess: UInt32
}

actor VirtualTree {
    private(set) var connections: [String: VirtualConnectionRecord] = [:]
    /// connectionLabel 안에서 displayName 충돌 시 ` (2)`, ` (3)` suffix 카운터.
    private var displayNameSuffixCounters: [String: [String: Int]] = [:]

    func addConnection(label: String, displayName: String) {
        if connections[label] != nil {
            connections[label]?.displayName = displayName
            return
        }
        connections[label] = VirtualConnectionRecord(connectionLabel: label, displayName: displayName)
    }

    @discardableResult
    func removeConnection(label: String) -> [UUID] {
        guard let record = connections.removeValue(forKey: label) else { return [] }
        displayNameSuffixCounters.removeValue(forKey: label)
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
        connections[connectionLabel] = connection
        return true
    }

    @discardableResult
    func removeMountSession(_ id: UUID) -> VirtualMountSessionRecord? {
        for (label, var connection) in connections {
            if let removed = connection.mountSessions.removeValue(forKey: id) {
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
