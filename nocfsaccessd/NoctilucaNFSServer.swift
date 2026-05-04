//
//  NoctilucaNFSServer.swift
//  nocfsaccessd
//
//  ``NFSServer`` 의 nocfsaccessd 측 구현. Stage E 의 본 버전은:
//
//  - virtual tree 의 root / 1단계 connection / 2단계 mount session 디렉토리는
//    데몬 자체에서 응답.
//  - active connection 이 0 일 때 root 에 정적 ``_README.txt`` 노출.
//  - mount session 안의 실제 파일 트리 (host = navigator file) 는 Stage F 에서
//    NocFSAccessHostProtocol 위임으로 채워진다 — 본 stage 에서는 모두
//    ``.notSupported`` throw.
//

import Foundation
import OSLog

import NanoNFS
import NocFSAccessXPC

actor NoctilucaNFSServer: NFSServer {

    private let virtualTree: VirtualTree
    private let handleTable: HandleTable

    private static let readmeBody: String = """
    이 폴더는 Noctiluca 의 원격 파일 공유 기능을 위해 마운트되었습니다.

    원격 클라이언트가 접속하여 파일을 공유하면, 이 README 는 자동으로
    사라지고 공유된 항목들이 이 폴더 아래에 나타납니다.

    -------------------------------------------------------------------

    This folder was mounted for Noctiluca's remote file-sharing feature.

    Once a remote client connects and shares files, this README will
    disappear automatically and the shared entries will appear here.
    """

    init(virtualTree: VirtualTree, handleTable: HandleTable) {
        self.virtualTree = virtualTree
        self.handleTable = handleTable
    }

    // MARK: - Helpers

    private static let dirMode: UInt32 = 0o755 | UInt32(S_IFDIR)
    private static let fileMode: UInt32 = 0o444 | UInt32(S_IFREG)

    private func decodeHandle(_ fh: NFSFileHandle) async throws -> (id: UInt64, entry: HandleEntry) {
        guard let id = HandleTable.decode(fh.bytes) else {
            throw NFSError.badHandle
        }
        guard let entry = await handleTable.get(id) else {
            throw NFSError.stale
        }
        return (id, entry)
    }

    private func directoryStat(fileid: UInt64) -> NFSStat {
        let now = NFSTime.now()
        return NFSStat(
            type: .directory,
            mode: Self.dirMode,
            nlink: 2,
            uid: UInt32(getuid()),
            gid: UInt32(getgid()),
            size: 0,
            used: 0,
            fileid: fileid,
            atime: now, mtime: now, ctime: now
        )
    }

    private func readmeStat() -> NFSStat {
        let now = NFSTime.now()
        let bodyData = Self.readmeBody.data(using: .utf8) ?? Data()
        return NFSStat(
            type: .regularFile,
            mode: Self.fileMode,
            nlink: 1,
            uid: UInt32(getuid()),
            gid: UInt32(getgid()),
            size: UInt64(bodyData.count),
            used: UInt64(bodyData.count),
            fileid: HandleTable.readmeEntryId,
            atime: now, mtime: now, ctime: now
        )
    }

    // MARK: - Root

    func root() async throws -> NFSFileHandle {
        return NFSFileHandle(HandleTable.encode(HandleTable.rootEntryId))
    }

    // MARK: - Metadata

    func access(handle: NFSFileHandle, mask: NFSAccess) async throws -> NFSAccess {
        // 모든 가상 entry 는 read-only 로 노출 (실제 read/write 권한은 host 위임 시 결정).
        return mask.intersection([.read, .lookup])
    }

    func getattr(handle: NFSFileHandle) async throws -> NFSStat {
        let (id, entry) = try await decodeHandle(handle)
        switch entry.kind {
        case .root, .connection, .mountSession:
            return directoryStat(fileid: id)
        case .readme:
            return readmeStat()
        case .hostFile:
            // Stage F 에서 host XPC 위임으로 채워질 부분.
            throw NFSError.notSupported
        }
    }

    func setattr(handle: NFSFileHandle, stateid: NFSStateID?, patch: NFSAttributesPatch) async throws -> NFSStat {
        throw NFSError.readOnly
    }

    // MARK: - Directory

    func lookup(parent: NFSFileHandle, name: String) async throws -> NFSFileHandle {
        let (_, entry) = try await decodeHandle(parent)
        switch entry.kind {
        case .root:
            return try await lookupInRoot(name: name)
        case .connection:
            guard let label = entry.connectionLabel else { throw NFSError.badHandle }
            return try await lookupInConnection(label: label, name: name)
        case .mountSession:
            // Stage F: host XPC 위임.
            throw NFSError.notSupported
        case .readme, .hostFile:
            throw NFSError.notDirectory
        }
    }

    private func lookupInRoot(name: String) async throws -> NFSFileHandle {
        if name == "_README.txt", await virtualTree.shouldShowReadme() {
            return NFSFileHandle(HandleTable.encode(HandleTable.readmeEntryId))
        }
        // connection label 매칭.
        let snapshot = await virtualTree.snapshotConnections()
        guard let connection = snapshot.first(where: { $0.connectionLabel == name }) else {
            throw NFSError.noEntry
        }
        let entry = HandleEntry(
            kind: .connection,
            connectionLabel: connection.connectionLabel,
            mountSessionId: nil, hostHandleId: nil, path: nil
        )
        let id = await handleTable.issue(entry)
        return NFSFileHandle(HandleTable.encode(id))
    }

    private func lookupInConnection(label: String, name: String) async throws -> NFSFileHandle {
        let snapshot = await virtualTree.snapshotConnections()
        guard let connection = snapshot.first(where: { $0.connectionLabel == label }) else {
            throw NFSError.stale
        }
        guard let session = connection.mountSessions.values.first(where: { $0.displayName == name }) else {
            throw NFSError.noEntry
        }
        let entry = HandleEntry(
            kind: .mountSession,
            connectionLabel: label,
            mountSessionId: session.id,
            hostHandleId: nil, path: nil
        )
        let id = await handleTable.issue(entry)
        return NFSFileHandle(HandleTable.encode(id))
    }

    func lookupParent(of handle: NFSFileHandle) async throws -> NFSFileHandle {
        let (_, entry) = try await decodeHandle(handle)
        switch entry.kind {
        case .root:
            return handle  // root 의 parent 는 root 자신.
        case .readme:
            return try await root()
        case .connection:
            return try await root()
        case .mountSession:
            guard let label = entry.connectionLabel else { throw NFSError.badHandle }
            let connEntry = HandleEntry(
                kind: .connection, connectionLabel: label,
                mountSessionId: nil, hostHandleId: nil, path: nil
            )
            let id = await handleTable.issue(connEntry)
            return NFSFileHandle(HandleTable.encode(id))
        case .hostFile:
            throw NFSError.notSupported
        }
    }

    func readdir(handle: NFSFileHandle, cookie: UInt64, cookieVerifier: UInt64, maxEntries: Int) async throws -> NFSDirList {
        let (_, entry) = try await decodeHandle(handle)
        switch entry.kind {
        case .root:
            return try await readdirRoot(cookie: cookie, maxEntries: maxEntries)
        case .connection:
            guard let label = entry.connectionLabel else { throw NFSError.badHandle }
            return try await readdirConnection(label: label, cookie: cookie, maxEntries: maxEntries)
        case .mountSession:
            // Stage F: host XPC 위임.
            throw NFSError.notSupported
        case .readme, .hostFile:
            throw NFSError.notDirectory
        }
    }

    private func readdirRoot(cookie: UInt64, maxEntries: Int) async throws -> NFSDirList {
        var entries: [NFSDirEntry] = []
        var nextCookie: UInt64 = cookie

        if await virtualTree.shouldShowReadme() {
            if cookie < 1 {
                entries.append(NFSDirEntry(
                    fileid: HandleTable.readmeEntryId,
                    name: "_README.txt",
                    attrs: readmeStat()
                ))
                nextCookie = 1
            }
        }

        let connections = await virtualTree.snapshotConnections()
        for (i, connection) in connections.enumerated() {
            let positional = UInt64(i + 2)  // 0=reserved, 1=README
            if positional <= cookie { continue }
            if entries.count >= maxEntries { break }
            entries.append(NFSDirEntry(
                fileid: positional,
                name: connection.connectionLabel,
                attrs: directoryStat(fileid: positional)
            ))
            nextCookie = positional
        }

        let exhausted = entries.count == 0 || (entries.last.map { _ in true } ?? false && nextCookie >= UInt64(connections.count + 1))
        return NFSDirList(entries: entries, nextCookie: exhausted ? nil : nextCookie, verifier: 0, eof: exhausted)
    }

    private func readdirConnection(label: String, cookie: UInt64, maxEntries: Int) async throws -> NFSDirList {
        let snapshot = await virtualTree.snapshotConnections()
        guard let connection = snapshot.first(where: { $0.connectionLabel == label }) else {
            throw NFSError.stale
        }
        let sessions = Array(connection.mountSessions.values).sorted { $0.displayName < $1.displayName }
        var entries: [NFSDirEntry] = []
        var nextCookie: UInt64 = cookie
        for (i, session) in sessions.enumerated() {
            let positional = UInt64(i + 1)
            if positional <= cookie { continue }
            if entries.count >= maxEntries { break }
            entries.append(NFSDirEntry(
                fileid: positional,
                name: session.displayName,
                attrs: directoryStat(fileid: positional)
            ))
            nextCookie = positional
        }
        let exhausted = nextCookie >= UInt64(sessions.count)
        return NFSDirList(entries: entries, nextCookie: exhausted ? nil : nextCookie, verifier: 0, eof: exhausted)
    }

    // MARK: - Create / remove / move (모두 stage F-G 에서 host 위임)

    func create(parent: NFSFileHandle, name: String, type: NFSObjectType, attrs: NFSAttributesPatch) async throws -> NFSFileHandle {
        throw NFSError.readOnly
    }

    func remove(parent: NFSFileHandle, name: String) async throws {
        throw NFSError.readOnly
    }

    func rename(srcParent: NFSFileHandle, srcName: String, dstParent: NFSFileHandle, dstName: String) async throws {
        throw NFSError.readOnly
    }

    func link(target: NFSFileHandle, parent: NFSFileHandle, name: String) async throws {
        throw NFSError.notSupported
    }

    func readlink(handle: NFSFileHandle) async throws -> String {
        throw NFSError.notSupported
    }

    // MARK: - OPEN / CLOSE

    func open(parent: NFSFileHandle, name: String,
              share: NFSShareAccess, deny: NFSShareDeny,
              owner: NFSOpenOwner,
              wantDelegation: NFSDelegationHint,
              create: NFSCreateMode) async throws -> (handle: NFSFileHandle, result: NFSOpenResult) {
        // _README.txt 는 read-only 로 open 가능.
        let (_, parentEntry) = try await decodeHandle(parent)
        if parentEntry.kind == .root && name == "_README.txt", await virtualTree.shouldShowReadme() {
            let fh = NFSFileHandle(HandleTable.encode(HandleTable.readmeEntryId))
            let stateid = NFSStateID.bypass
            return (fh, NFSOpenResult(stateid: stateid, rflags: [], delegation: .none))
        }
        // 그 외는 stage F 에서 host 위임.
        throw NFSError.notSupported
    }

    func openConfirm(handle: NFSFileHandle, stateid: NFSStateID, seqid: UInt32) async throws -> NFSStateID {
        return stateid
    }

    func openDowngrade(handle: NFSFileHandle, stateid: NFSStateID, share: NFSShareAccess, deny: NFSShareDeny) async throws -> NFSStateID {
        return stateid
    }

    func close(handle: NFSFileHandle, stateid: NFSStateID) async throws {
        // _README.txt close 는 무동작. host file 은 stage F.
        let (_, entry) = try await decodeHandle(handle)
        if entry.kind == .readme { return }
        throw NFSError.notSupported
    }

    // MARK: - I/O

    func read(handle: NFSFileHandle, stateid: NFSStateID, offset: UInt64, count: Int) async throws -> NFSReadResult {
        let (_, entry) = try await decodeHandle(handle)
        switch entry.kind {
        case .readme:
            let body = Self.readmeBody.data(using: .utf8) ?? Data()
            if offset >= UInt64(body.count) {
                return NFSReadResult(data: Data(), eof: true)
            }
            let start = Int(offset)
            let end = min(body.count, start + count)
            let chunk = body.subdata(in: start..<end)
            return NFSReadResult(data: chunk, eof: end >= body.count)
        case .hostFile:
            throw NFSError.notSupported
        default:
            throw NFSError.isDirectory
        }
    }

    func write(handle: NFSFileHandle, stateid: NFSStateID, offset: UInt64, stability: NFSWriteStability, data: Data) async throws -> NFSWriteResult {
        throw NFSError.readOnly
    }

    func commit(handle: NFSFileHandle, offset: UInt64, count: UInt64) async throws -> UInt64 {
        return 0
    }

    // MARK: - Locking

    func lock(handle: NFSFileHandle, type: NFSLockType, range: NFSLockRange, owner: NFSLockOwner, reclaim: Bool, stateid: NFSStateID) async throws -> NFSStateID {
        throw NFSError.notSupported
    }

    func lockTest(handle: NFSFileHandle, type: NFSLockType, range: NFSLockRange, owner: NFSLockOwner) async throws -> NFSLockTestResult {
        throw NFSError.notSupported
    }

    func unlock(handle: NFSFileHandle, range: NFSLockRange, stateid: NFSStateID) async throws -> NFSStateID {
        throw NFSError.notSupported
    }
}
