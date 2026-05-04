//
//  VirtualTree.swift
//  nocfsaccessd
//
//  Sirius connection / mount session 의 가상 디렉토리 트리. 모든 갱신은 호스트
//  앱의 push event (addConnection / removeConnection / addMountSession /
//  removeMountSession) 로만 일어나며, 데몬은 polling 하지 않는다.
//

import Foundation
import OSLog

import NocFSAccessXPC

/// 1단계 namespace 의 entry. `0001-cheesekun` 형식의 connectionLabel 을 갖는다.
struct VirtualConnectionRecord: Sendable {
    let connectionLabel: String
    var displayName: String
    var mountSessions: [UUID: VirtualMountSessionRecord] = [:]
}

/// 2단계 namespace 의 entry. `addMountSession` 으로 들어오는 descriptor 를 그대로
/// 보관.
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
            DaemonLogger.vtree.warning("addConnection: label \(label, privacy: .public) already exists; replacing displayName.")
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

    func addMountSession(_ descriptor: NocFSMountSessionDescriptor) -> Bool {
        guard var connection = connections[descriptor.connectionLabel] else {
            DaemonLogger.vtree.error("addMountSession: connectionLabel \(descriptor.connectionLabel, privacy: .public) not found.")
            return false
        }
        guard let sessionId = UUID(uuidString: descriptor.mountSessionId) else {
            DaemonLogger.vtree.error("addMountSession: mountSessionId not a UUID: \(descriptor.mountSessionId, privacy: .public)")
            return false
        }
        let displayName = sanitizedAndDeduped(descriptor.displayName, in: descriptor.connectionLabel)
        let record = VirtualMountSessionRecord(
            id: sessionId,
            connectionLabel: descriptor.connectionLabel,
            displayName: displayName,
            grantedAccess: descriptor.grantedAccess
        )
        connection.mountSessions[sessionId] = record
        connections[descriptor.connectionLabel] = connection
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

    /// `/` / NUL → `_` 치환 + 같은 connection 안에서 displayName 중복 시 ` (2)`, ` (3)` suffix.
    private func sanitizedAndDeduped(_ raw: String, in connectionLabel: String) -> String {
        var sanitized = raw
        sanitized = sanitized.replacingOccurrences(of: "/", with: "_")
        sanitized = sanitized.replacingOccurrences(of: "\u{0000}", with: "_")
        if sanitized.isEmpty { sanitized = "(unnamed)" }

        // 같은 connection 안의 기존 displayName 들과 충돌하면 suffix.
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
