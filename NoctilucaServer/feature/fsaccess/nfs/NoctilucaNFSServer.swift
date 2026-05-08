//
//  NoctilucaNFSServer.swift
//  NoctilucaServer
//
//  ``NFSServer`` 의 host-app-internal 구현. 데몬 분리를 포기한 옵션 A 디자인
//  에서는 본 액터가 NFS 서버이자 fsaccess_mount channel dispatch 의 양쪽을
//  모두 책임진다 (이전 NocFSAccessHostXPCExport 의 16개 메서드 dispatch 가
//  여기 안에 직접 흡수).
//
//  - 가상 트리의 root / 1단계 connection / 2단계 mount session 디렉토리는 본
//    actor 자체에서 응답.
//  - mount session 안의 실제 파일 트리는 ``FSAccessRequestRouter`` 에 등록된
//    ``FSAccessMountChannel`` 을 통해 navigator 에 fsaccess_mount 메시지를
//    *발신* 해 응답을 받음.
//

import Foundation
import OSLog

import NanoNFS

import SiriusKit

actor NoctilucaNFSServer: NFSServer {

    private let virtualTree: VirtualTree
    private let handleTable: HandleTable
    private let logger = Logger(subsystem: "pl.unstabler.noctiluca.fsaccess", category: "nfs")

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

    // MARK: - Stat helpers

    private static let dirMode: UInt32 = 0o755 | UInt32(S_IFDIR)
    private static let fileMode: UInt32 = 0o444 | UInt32(S_IFREG)

    /// `_README.txt` 의 timestamp. README 본문은 변하지 않으므로 부팅시 stamp.
    private static let readmeTime: NFSTime = NFSTime.now()

    /// `.metadata_never_index` sentinel 파일 이름. 가상 트리 root 에서만 노출.
    /// macOS Spotlight 가 이 파일 존재만 보고 볼륨 통째로 인덱싱 skip.
    /// readdir 에는 노출하지 않고 lookup-only — dot file 이라 Spotlight 의
    /// 표준 probe (`stat()`) 만으로 충분.
    private static let metadataNeverIndexName: String = ".metadata_never_index"

    private func decodeHandle(_ fh: NFSFileHandle) async throws -> (id: UInt64, entry: HandleEntry) {
        guard let id = HandleTable.decode(fh.bytes) else {
            logger.error("decodeHandle: bad fh — bytes=\(fh.bytes.count) hex=\(fh.bytes.map { String(format: "%02x", $0) }.joined())")
            throw NFSError.badHandle
        }
        guard let entry = await handleTable.get(id) else {
            logger.error("decodeHandle: stale fh — id=\(id) (entry no longer in HandleTable)")
            throw NFSError.stale
        }
        return (id, entry)
    }

    private func directoryStat(fileid: UInt64, mtime: NFSTime) -> NFSStat {
        return NFSStat(
            type: .directory, mode: Self.dirMode, nlink: 2,
            uid: UInt32(getuid()), gid: UInt32(getgid()),
            size: 0, used: 0, fileid: fileid,
            atime: mtime, mtime: mtime, ctime: mtime
        )
    }

    private func readmeStat() -> NFSStat {
        let stamp = Self.readmeTime
        let body = Self.readmeBody.data(using: .utf8) ?? Data()
        return NFSStat(
            type: .regularFile, mode: Self.fileMode, nlink: 1,
            uid: UInt32(getuid()), gid: UInt32(getgid()),
            size: UInt64(body.count), used: UInt64(body.count),
            fileid: HandleTable.readmeEntryId,
            atime: stamp, mtime: stamp, ctime: stamp
        )
    }

    /// `.metadata_never_index` 의 stat — 0-byte regular file. 본문은 비어있고
    /// timestamp 는 readme 와 같이 부팅시 stamp 로 stable.
    private func metadataNeverIndexStat() -> NFSStat {
        let stamp = Self.readmeTime
        return NFSStat(
            type: .regularFile, mode: Self.fileMode, nlink: 1,
            uid: UInt32(getuid()), gid: UInt32(getgid()),
            size: 0, used: 0,
            fileid: HandleTable.metadataNeverIndexEntryId,
            atime: stamp, mtime: stamp, ctime: stamp
        )
    }

    private static func nfsObjectType(from sirius: FileType) -> NFSObjectType {
        switch sirius {
        case .file: return .regularFile
        case .directory: return .directory
        case .symlink: return .symbolicLink
        case .unknown, .other: return .regularFile
        default: return .regularFile
        }
    }

    private static func nfsTime(epochMs: Int64) -> NFSTime {
        let secs = epochMs / 1000
        let ms = epochMs % 1000
        return NFSTime(seconds: secs, nseconds: UInt32(ms * 1_000_000))
    }

    private static func makeNFSStat(from sirius: FileStat, fileid: UInt64) -> NFSStat {
        let mtime = nfsTime(epochMs: sirius.mtimeMs)
        let atime = sirius.atimeMs > 0 ? nfsTime(epochMs: sirius.atimeMs) : mtime
        let ctime = mtime
        return NFSStat(
            type: nfsObjectType(from: sirius.type),
            mode: sirius.mode == 0 ? Self.fileMode : sirius.mode,
            nlink: 1,
            uid: UInt32(getuid()),
            gid: UInt32(getgid()),
            size: sirius.size,
            used: sirius.size,
            fileid: fileid,
            atime: atime, mtime: mtime, ctime: ctime
        )
    }

    // MARK: - Channel lookup

    /// mountSessionId 로 활성 ``FSAccessMountChannel`` 을 조회.
    private func channel(for sessionId: UUID) async throws -> FSAccessMountChannel {
        guard let channel = await FSAccessRequestRouter.shared.channel(for: sessionId) else {
            throw NFSError.stale
        }
        return channel
    }

    /// `FileSystemErrorCode` → `NFSError` 직접 환원.
    private static func nfsError(from info: ErrorInfo?) -> NFSError {
        guard let info else { return .serverFault }
        switch info.code {
        case .notFound: return .noEntry
        case .alreadyExists: return .exists
        case .notDirectory: return .notDirectory
        case .isDirectory: return .isDirectory
        case .notEmpty: return .notEmpty
        case .pathTooLong: return .nameTooLong
        case .crossDevice: return .crossDevice
        case .accessDenied: return .accessDenied
        case .permissionDenied: return .permission
        case .readOnlyFilesystem: return .readOnly
        case .diskFull: return .noSpace
        case .fileTooLarge: return .fileTooBig
        case .quotaExceeded: return .dirQuota
        case .invalidHandle: return .badHandle
        case .invalidArgument: return .invalid
        case .notSupported: return .notSupported
        case .invalidPath: return .invalid
        case .invalidSession, .notMounted, .channelClosing, .staleHandle: return .stale
        case .consentDenied, .policyViolation: return .accessDenied
        case .ioError: return .io
        case .busy: return .fileBusy
        default: return .serverFault
        }
    }

    private func joinPath(parent: String, name: String) -> String {
        if parent.isEmpty || parent == "/" { return "/" + name }
        return parent + "/" + name
    }

    private func parentPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return "" }
        let parent = String(trimmed[..<lastSlash])
        return parent.isEmpty ? "/" : parent
    }

    // MARK: - Root

    func root() async throws -> NFSFileHandle {
        return NFSFileHandle(HandleTable.encode(HandleTable.rootEntryId))
    }

    // MARK: - Metadata

    func access(handle: NFSFileHandle, mask: NFSAccess) async throws -> NFSAccess {
        // mask 그대로 echo. 실제 권한 검사는 navigator 가 read/write 시점에 한다.
        // .read / .lookup 만 echo 하면 ls/cp 의 사전 권한 체크에서 EPERM 발생.
        return mask
    }

    func getattr(handle: NFSFileHandle) async throws -> NFSStat {
        let (id, entry) = try await decodeHandle(handle)
        switch entry.kind {
        case .root:
            let mtime = await virtualTree.rootMtime
            return directoryStat(fileid: id, mtime: mtime)
        case .connection:
            guard let label = entry.connectionLabel else { throw NFSError.badHandle }
            let mtime = (await virtualTree.connectionMtime(label: label)) ?? .now()
            return directoryStat(fileid: id, mtime: mtime)
        case .mountSession:
            return try await getattrMountSession(handleEntry: entry, fileid: id)
        case .readme:
            return readmeStat()
        case .metadataNeverIndex:
            return metadataNeverIndexStat()
        case .hostFile:
            return try await getattrHostFile(handleEntry: entry, fileid: id)
        }
    }

    /// mountSession 의 getattr 은 navigator 측 root dir (`/`) 의 stat 결과를 그대로
    /// 사용한다. NFSv4 client 가 이 mtime 을 보고 자식 readdir 을 invalidate
    /// 할지 결정하기 때문에, navigator-side 실제 변경이 그대로 반영되어야 한다.
    /// stat 호출 실패 시에는 virtualTree 의 fallback mtime 사용.
    private func getattrMountSession(handleEntry: HandleEntry, fileid: UInt64) async throws -> NFSStat {
        guard let mountSessionId = handleEntry.mountSessionId else { throw NFSError.badHandle }
        let channel = try await channel(for: mountSessionId)
        let response = try await channel.sendStat(path: "/", followSymlinks: true)
        if response.success, let stat = response.stat {
            // navigator-side mountSession root 의 type 은 항상 directory.
            return Self.makeNFSStat(from: stat, fileid: fileid)
        }
        let fallback = (await virtualTree.mountSessionMtime(id: mountSessionId)) ?? .now()
        return directoryStat(fileid: fileid, mtime: fallback)
    }

    private func getattrHostFile(handleEntry: HandleEntry, fileid: UInt64) async throws -> NFSStat {
        guard let mountSessionId = handleEntry.mountSessionId,
              let hostFileId = handleEntry.hostFileId else {
            throw NFSError.badHandle
        }
        let channel = try await channel(for: mountSessionId)
        // 캐시 hit 시 navigator wire 호출 skip. Finder / Spotlight 의 GETATTR
        // 폭주가 client attr cache 를 뚫고 들어오는 케이스가 핫스팟이라 가장
        // ROI 큰 단축 경로.
        if let cached = await channel.pathMap.cachedStat(forHostHandleId: hostFileId) {
            return Self.makeNFSStat(from: cached, fileid: fileid)
        }
        // GETATTR 는 stateid 인자가 없는 op (RFC 7530 §16.7). hostFile 에 살아
        // 있는 OPEN slot 이 있으면 그 navHandle 로 fstat (가장 정확). 없으면
        // path 기반 sendStat 로 fallback.
        if let slot = await channel.openSlotTable.bestSlot(forHostFileId: hostFileId) {
            let response = try await channel.sendFStat(handleId: slot.navigatorHandleId)
            guard response.success, let stat = response.stat else {
                throw Self.nfsError(from: response.error)
            }
            await channel.pathMap.updateStat(forHostHandleId: hostFileId, stat: stat)
            return Self.makeNFSStat(from: stat, fileid: fileid)
        }
        let path = await channel.pathMap.path(forHostHandleId: hostFileId)
        let response = try await channel.sendStat(path: path.isEmpty ? "/" : path, followSymlinks: true)
        guard response.success, let stat = response.stat else {
            throw Self.nfsError(from: response.error)
        }
        await channel.pathMap.updateStat(forHostHandleId: hostFileId, stat: stat)
        return Self.makeNFSStat(from: stat, fileid: fileid)
    }

    func setattr(handle: NFSFileHandle, stateid: NFSStateID?, patch: NFSAttributesPatch) async throws -> NFSStat {
        let (id, entry) = try await decodeHandle(handle)
        guard entry.kind == .hostFile,
              let mountSessionId = entry.mountSessionId,
              let hostFileId = entry.hostFileId else {
            throw NFSError.readOnly
        }
        let channel = try await channel(for: mountSessionId)
        // size 변경은 FTruncate 로 매핑. 그 외 (mode/time) 는 best-effort NOOP.
        if let size = patch.size {
            // RFC 7530 §16.32 — SETATTR 의 size 변경은 OPEN stateid 를 요구.
            // anonymous / nil 은 거부.
            guard let stateid, !Self.isAnonymous(stateid) else {
                logger.error("setattr(size): nil/anonymous stateid not permitted")
                throw NFSError.badStateid
            }
            guard let slot = await channel.openSlotTable.lookup(stateidOther: stateid.other) else {
                logger.error("setattr(size): stateid lookup miss — hostFileId=\(hostFileId)")
                throw NFSError.staleStateid
            }
            let response = try await channel.sendFTruncate(handleId: slot.navigatorHandleId, length: size)
            guard response.success else { throw Self.nfsError(from: response.error) }
            await channel.pathMap.invalidateStat(forHostHandleId: hostFileId)
        }
        return try await getattrHostFile(handleEntry: entry, fileid: id)
    }

    // MARK: - Directory

    func lookup(parent: NFSFileHandle, name: String) async throws -> NFSFileHandle {
        let (parentId, entry) = try await decodeHandle(parent)
        logger.debug("lookup: parentId=\(parentId) parentKind=\(String(describing: entry.kind)) name=\(name)")
        switch entry.kind {
        case .root:
            return try await lookupInRoot(name: name)
        case .connection:
            guard let label = entry.connectionLabel else { throw NFSError.badHandle }
            return try await lookupInConnection(label: label, name: name)
        case .mountSession:
            guard let mountSessionId = entry.mountSessionId else { throw NFSError.badHandle }
            return try await lookupInMountSession(
                mountSessionId: mountSessionId, parentPath: "", name: name,
                connectionLabel: entry.connectionLabel
            )
        case .hostFile:
            guard let mountSessionId = entry.mountSessionId,
                  let hostFileId = entry.hostFileId else {
                throw NFSError.badHandle
            }
            let channel = try await channel(for: mountSessionId)
            let parentPath = await channel.pathMap.path(forHostHandleId: hostFileId)
            return try await lookupInMountSession(
                mountSessionId: mountSessionId, parentPath: parentPath, name: name,
                connectionLabel: entry.connectionLabel
            )
        case .readme, .metadataNeverIndex:
            throw NFSError.notDirectory
        }
    }

    private func lookupInRoot(name: String) async throws -> NFSFileHandle {
        if name == "_README.txt", await virtualTree.shouldShowReadme() {
            return NFSFileHandle(HandleTable.encode(HandleTable.readmeEntryId))
        }
        if name == Self.metadataNeverIndexName {
            return NFSFileHandle(HandleTable.encode(HandleTable.metadataNeverIndexEntryId))
        }
        let snapshot = await virtualTree.snapshotConnections()
        guard let connection = snapshot.first(where: { $0.connectionLabel == name }) else {
            throw NFSError.noEntry
        }
        let entry = HandleEntry(
            kind: .connection, connectionLabel: connection.connectionLabel,
            mountSessionId: nil, hostFileId: nil
        )
        let id = await handleTable.issueIfAbsent(
            entry, key: HandleTable.keyForConnection(connection.connectionLabel)
        )
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
            kind: .mountSession, connectionLabel: label,
            mountSessionId: session.id, hostFileId: nil
        )
        let id = await handleTable.issueIfAbsent(
            entry, key: HandleTable.keyForMountSession(session.id)
        )
        return NFSFileHandle(HandleTable.encode(id))
    }

    private func lookupInMountSession(mountSessionId: UUID,
                                      parentPath: String,
                                      name: String,
                                      connectionLabel: String?) async throws -> NFSFileHandle {
        let channel = try await channel(for: mountSessionId)
        let childPath = joinPath(parent: parentPath, name: name)
        // 캐시 hit 이면 'entry 가 존재한다' 는 사실까지 같이 확인된 상태.
        // sendStat 을 skip 하고 fh 만 발급 — Finder 의 LOOKUP 폭주 단축 경로.
        let cachedStat = await channel.pathMap.cachedStat(forPath: childPath)
        let hostFileId: UInt64
        if cachedStat == nil {
            let response = try await channel.sendStat(path: childPath, followSymlinks: false)
            guard response.success else { throw Self.nfsError(from: response.error) }
            if let stat = response.stat {
                hostFileId = await channel.pathMap.issueIfAbsent(path: childPath, withStat: stat)
            } else {
                hostFileId = await channel.pathMap.issueIfAbsent(path: childPath)
            }
        } else {
            hostFileId = await channel.pathMap.issueIfAbsent(path: childPath)
        }
        let entry = HandleEntry(
            kind: .hostFile,
            connectionLabel: connectionLabel,
            mountSessionId: mountSessionId,
            hostFileId: hostFileId
        )
        let id = await handleTable.issueIfAbsent(
            entry, key: HandleTable.keyForHostFile(mountSessionId: mountSessionId, path: childPath)
        )
        return NFSFileHandle(HandleTable.encode(id))
    }

    func lookupParent(of handle: NFSFileHandle) async throws -> NFSFileHandle {
        let (_, entry) = try await decodeHandle(handle)
        switch entry.kind {
        case .root: return handle
        case .readme, .metadataNeverIndex, .connection: return try await root()
        case .mountSession:
            guard let label = entry.connectionLabel else { throw NFSError.badHandle }
            let connEntry = HandleEntry(
                kind: .connection, connectionLabel: label,
                mountSessionId: nil, hostFileId: nil
            )
            let id = await handleTable.issueIfAbsent(connEntry, key: HandleTable.keyForConnection(label))
            return NFSFileHandle(HandleTable.encode(id))
        case .hostFile:
            guard let mountSessionId = entry.mountSessionId,
                  let hostFileId = entry.hostFileId else { throw NFSError.badHandle }
            let channel = try await channel(for: mountSessionId)
            let path = await channel.pathMap.path(forHostHandleId: hostFileId)
            let parent = parentPath(of: path)
            if parent.isEmpty {
                // mount session root.
                let mountEntry = HandleEntry(
                    kind: .mountSession,
                    connectionLabel: entry.connectionLabel,
                    mountSessionId: mountSessionId, hostFileId: nil
                )
                let id = await handleTable.issueIfAbsent(
                    mountEntry, key: HandleTable.keyForMountSession(mountSessionId)
                )
                return NFSFileHandle(HandleTable.encode(id))
            }
            let parentHostId = await channel.pathMap.issueIfAbsent(path: parent)
            let parentEntry = HandleEntry(
                kind: .hostFile,
                connectionLabel: entry.connectionLabel,
                mountSessionId: mountSessionId, hostFileId: parentHostId
            )
            let id = await handleTable.issueIfAbsent(
                parentEntry,
                key: HandleTable.keyForHostFile(mountSessionId: mountSessionId, path: parent)
            )
            return NFSFileHandle(HandleTable.encode(id))
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
            guard let mountSessionId = entry.mountSessionId else { throw NFSError.badHandle }
            return try await readdirMount(mountSessionId: mountSessionId, parentPath: "/",
                                          connectionLabel: entry.connectionLabel,
                                          cookie: cookie, maxEntries: maxEntries)
        case .hostFile:
            guard let mountSessionId = entry.mountSessionId,
                  let hostFileId = entry.hostFileId else { throw NFSError.badHandle }
            let channel = try await channel(for: mountSessionId)
            let path = await channel.pathMap.path(forHostHandleId: hostFileId)
            return try await readdirMount(mountSessionId: mountSessionId,
                                          parentPath: path.isEmpty ? "/" : path,
                                          connectionLabel: entry.connectionLabel,
                                          cookie: cookie, maxEntries: maxEntries)
        case .readme, .metadataNeverIndex:
            throw NFSError.notDirectory
        }
    }

    private func readdirRoot(cookie: UInt64, maxEntries: Int) async throws -> NFSDirList {
        var entries: [NFSDirEntry] = []
        var nextCookie: UInt64 = cookie

        if await virtualTree.shouldShowReadme(), cookie < 1 {
            entries.append(NFSDirEntry(
                fileid: HandleTable.readmeEntryId,
                name: "_README.txt",
                attrs: readmeStat(),
                fileHandle: NFSFileHandle(HandleTable.encode(HandleTable.readmeEntryId))
            ))
            nextCookie = 1
        }

        let connections = await virtualTree.snapshotConnections()
        for (i, connection) in connections.enumerated() {
            let positional = UInt64(i + 2)
            if positional <= cookie { continue }
            if entries.count >= maxEntries { break }
            // fileid 는 lookup 결과의 entryId 와 동일해야 NFSv4 client cache 가
            // 정합. positional cookie 를 fileid 로 쓰면 Finder 의 LOOKUPP 검증
            // 시 fileid mismatch 로 directory tree 가 cycle 처럼 보인다.
            let connEntry = HandleEntry(
                kind: .connection, connectionLabel: connection.connectionLabel,
                mountSessionId: nil, hostFileId: nil
            )
            let entryId = await handleTable.issueIfAbsent(
                connEntry, key: HandleTable.keyForConnection(connection.connectionLabel)
            )
            // entry 별 fh 도 함께 응답. nanonfs 가 attrRequest 의 FATTR4_FILEHANDLE
            // 에 대해 entry.fileHandle ?? parentFh 사용 — Finder 가 mismatch 로
            // entry 를 drop 하지 않게 하려면 반드시 entry-specific fh 가 필요.
            entries.append(NFSDirEntry(
                fileid: entryId, name: connection.connectionLabel,
                attrs: directoryStat(fileid: entryId, mtime: connection.mtime),
                fileHandle: NFSFileHandle(HandleTable.encode(entryId))
            ))
            nextCookie = positional
        }

        let exhausted = entries.count == 0 || nextCookie >= UInt64(connections.count + 1)
        return NFSDirList(entries: entries, nextCookie: exhausted ? nil : nextCookie, verifier: 0, eof: exhausted)
    }

    private func readdirConnection(label: String, cookie: UInt64, maxEntries: Int) async throws -> NFSDirList {
        let snapshot = await virtualTree.snapshotConnections()
        guard let connection = snapshot.first(where: { $0.connectionLabel == label }) else {
            throw NFSError.stale
        }
        let sessions = Array(connection.mountSessions.values).sorted { $0.displayName < $1.displayName }
        let nameList = sessions.map { $0.displayName }.joined(separator: ",")
        logger.info("readdirConnection: label=\(label) sessionCount=\(sessions.count) names=[\(nameList)]")
        var entries: [NFSDirEntry] = []
        var nextCookie: UInt64 = cookie
        for (i, session) in sessions.enumerated() {
            let positional = UInt64(i + 1)
            if positional <= cookie { continue }
            if entries.count >= maxEntries { break }
            // fileid 통일 — readdirRoot 와 같은 이유.
            let mountEntry = HandleEntry(
                kind: .mountSession, connectionLabel: label,
                mountSessionId: session.id, hostFileId: nil
            )
            let entryId = await handleTable.issueIfAbsent(
                mountEntry, key: HandleTable.keyForMountSession(session.id)
            )
            // readdir 의 entry attrs 는 virtualTree 가 보유한 등록 시점 mtime 사용.
            // mountSession 안의 진짜 navigator-side mtime 은 client 가 그 dir 안에
            // 진입할 때 GETATTR 로 다시 받는다 (getattrMountSession).
            entries.append(NFSDirEntry(
                fileid: entryId, name: session.displayName,
                attrs: directoryStat(fileid: entryId, mtime: session.mtime),
                fileHandle: NFSFileHandle(HandleTable.encode(entryId))
            ))
            nextCookie = positional
        }
        let exhausted = nextCookie >= UInt64(sessions.count)
        return NFSDirList(entries: entries, nextCookie: exhausted ? nil : nextCookie, verifier: 0, eof: exhausted)
    }

    private func readdirMount(mountSessionId: UUID,
                              parentPath: String,
                              connectionLabel: String?,
                              cookie: UInt64,
                              maxEntries: Int) async throws -> NFSDirList {
        let channel = try await channel(for: mountSessionId)
        logger.info("readdir: enter path=\(parentPath) maxEntries=\(maxEntries) cookie=\(cookie)")
        let openResponse = try await channel.sendOpen(
            path: parentPath,
            accessMode: .read,
            createDisposition: .openExisting,
            flags: [.directoryOnly],
            mode: 0
        )
        guard openResponse.success else {
            logger.error("readdir: OPEN failed for path=\(parentPath): \(openResponse.error?.message ?? "<no info>") code=\(openResponse.error?.code.rawValue ?? 0)")
            throw Self.nfsError(from: openResponse.error)
        }
        logger.debug("readdir: OPEN ok navHandle=\(openResponse.handleId)")
        let response = try await channel.sendReadDir(
            handleId: openResponse.handleId,
            maxEntries: UInt32(min(maxEntries, Int(UInt32.max)))
        )
        _ = try? await channel.sendClose(handleId: openResponse.handleId)
        guard response.success else {
            logger.error("readdir: ReadDir failed: \(response.error?.message ?? "<no info>") code=\(response.error?.code.rawValue ?? 0)")
            throw Self.nfsError(from: response.error)
        }
        logger.info("readdir: ReadDir ok entries=\(response.entries.count) isEnd=\(response.isEnd)")

        var entries: [NFSDirEntry] = []
        for (i, dirEntry) in response.entries.enumerated() {
            let stat = dirEntry.stat ?? FileStat(
                type: .unknown, size: 0, mode: 0,
                mtimeMs: 0, atimeMs: 0, btimeMs: 0,
                attributes: [], symlinkTarget: nil, metadata: [:]
            )
            // fileid / fh 모두 HandleTable 의 entryId 와 통일. lookup 결과 fh 와
            // readdir 응답 fh 가 같아야 NFSv4 client (Finder) 가 readdir attr
            // mask 의 FATTR4_FILEHANDLE 로 받은 fh 를 후속 GETATTR 등에서 그대로
            // 쓸 때 동일 entry 로 식별한다.
            let childPath = joinPath(parent: parentPath, name: dirEntry.name)
            // readdir 응답에 navigator 가 같이 보내준 stat 을 path 별로 캐시.
            // 직후 같은 entry 에 대해 들어오는 LOOKUP / GETATTR 가 wire 안 가게.
            let hostFileId: UInt64
            if let entryStat = dirEntry.stat {
                hostFileId = await channel.pathMap.issueIfAbsent(path: childPath, withStat: entryStat)
            } else {
                hostFileId = await channel.pathMap.issueIfAbsent(path: childPath)
            }
            let hostFileEntry = HandleEntry(
                kind: .hostFile,
                connectionLabel: connectionLabel,
                mountSessionId: mountSessionId,
                hostFileId: hostFileId
            )
            let entryId = await handleTable.issueIfAbsent(
                hostFileEntry,
                key: HandleTable.keyForHostFile(mountSessionId: mountSessionId, path: childPath)
            )
            let positionalCookie = cookie + UInt64(i + 1)
            entries.append(NFSDirEntry(
                fileid: entryId, name: dirEntry.name,
                attrs: Self.makeNFSStat(from: stat, fileid: entryId),
                fileHandle: NFSFileHandle(HandleTable.encode(entryId))
            ))
            _ = positionalCookie  // cookie 는 NFSDirList.nextCookie 에서만 사용.
        }
        let nextCookie = cookie + UInt64(entries.count)
        return NFSDirList(entries: entries, nextCookie: response.isEnd ? nil : nextCookie,
                          verifier: 0, eof: response.isEnd)
    }

    // MARK: - Create / remove / move

    func create(parent: NFSFileHandle, name: String, type: NFSObjectType, attrs: NFSAttributesPatch) async throws -> NFSFileHandle {
        let (_, entry) = try await decodeHandle(parent)
        let (mountSessionId, parentPath, connLabel) = try await mountContext(for: entry)
        let channel = try await channel(for: mountSessionId)
        let childPath = joinPath(parent: parentPath, name: name)
        if type == .directory {
            let response = try await channel.sendMkdir(path: childPath, mode: attrs.mode ?? 0o755)
            guard response.success else { throw Self.nfsError(from: response.error) }
            // parent 의 mtime / dirent 가 변경됨 → 캐시 무효화.
            await channel.pathMap.invalidateStat(forPath: parentPath)
            let hostId = await channel.pathMap.issueIfAbsent(path: childPath)
            let newEntry = HandleEntry(
                kind: .hostFile, connectionLabel: connLabel,
                mountSessionId: mountSessionId, hostFileId: hostId
            )
            let id = await handleTable.issueIfAbsent(
                newEntry,
                key: HandleTable.keyForHostFile(mountSessionId: mountSessionId, path: childPath)
            )
            return NFSFileHandle(HandleTable.encode(id))
        }
        // regular file → Open(createNew).
        //
        // NFSv4 CREATE 응답에는 stateid 가 없다 (RFC 7530 §16.4 — handle 만
        // 응답). navigator 가 createNew 후 떨어뜨린 navHandle 은 client 가
        // 어차피 직후 OPEN op 로 새 stateid+navHandle 을 다시 잡을 거라
        // 즉시 close 해 navigator-side handle leak 을 방지한다. 약간의 wire
        // 왕복이 추가되지만, OpenSlotTable 의 invariant (모든 active
        // navHandle 은 client 가 echo 가능한 stateid 의 slot 에 1:1 대응) 을
        // 깨지 않는 게 더 중요하다.
        let response = try await channel.sendOpen(
            path: childPath, accessMode: .readWrite,
            createDisposition: .createNew, flags: [], mode: attrs.mode ?? 0o644
        )
        guard response.success else { throw Self.nfsError(from: response.error) }
        _ = try? await channel.sendClose(handleId: response.handleId)
        await channel.pathMap.invalidateStat(forPath: parentPath)
        let hostId = await channel.pathMap.issueIfAbsent(path: childPath)
        let newEntry = HandleEntry(
            kind: .hostFile, connectionLabel: connLabel,
            mountSessionId: mountSessionId, hostFileId: hostId
        )
        let id = await handleTable.issueIfAbsent(
            newEntry,
            key: HandleTable.keyForHostFile(mountSessionId: mountSessionId, path: childPath)
        )
        return NFSFileHandle(HandleTable.encode(id))
    }

    func remove(parent: NFSFileHandle, name: String) async throws {
        let (_, entry) = try await decodeHandle(parent)
        let (mountSessionId, parentPath, _) = try await mountContext(for: entry)
        let channel = try await channel(for: mountSessionId)
        let childPath = joinPath(parent: parentPath, name: name)
        let stat = try await channel.sendStat(path: childPath, followSymlinks: false)
        guard stat.success, let s = stat.stat else { throw Self.nfsError(from: stat.error) }
        if s.type == .directory {
            let response = try await channel.sendRmdir(path: childPath)
            guard response.success else { throw Self.nfsError(from: response.error) }
        } else {
            let response = try await channel.sendUnlink(path: childPath)
            guard response.success else { throw Self.nfsError(from: response.error) }
        }
        // 삭제된 entry + parent dirent 모두 invalidate.
        await channel.pathMap.invalidateStat(forPath: childPath)
        await channel.pathMap.invalidateStat(forPath: parentPath)
    }

    func rename(srcParent: NFSFileHandle, srcName: String, dstParent: NFSFileHandle, dstName: String) async throws {
        let (_, srcEntry) = try await decodeHandle(srcParent)
        let (_, dstEntry) = try await decodeHandle(dstParent)
        guard srcEntry.mountSessionId != nil,
              srcEntry.mountSessionId == dstEntry.mountSessionId else {
            throw NFSError.crossDevice
        }
        let (mountSessionId, srcParentPath, _) = try await mountContext(for: srcEntry)
        let (_, dstParentPath, _) = try await mountContext(for: dstEntry)
        let channel = try await channel(for: mountSessionId)
        let oldPath = joinPath(parent: srcParentPath, name: srcName)
        let newPath = joinPath(parent: dstParentPath, name: dstName)
        let response = try await channel.sendRename(oldPath: oldPath, newPath: newPath)
        guard response.success else { throw Self.nfsError(from: response.error) }
        // src/dst entry + 양쪽 parent dirent 모두 invalidate.
        await channel.pathMap.invalidateStat(forPath: oldPath)
        await channel.pathMap.invalidateStat(forPath: newPath)
        await channel.pathMap.invalidateStat(forPath: srcParentPath)
        if srcParentPath != dstParentPath {
            await channel.pathMap.invalidateStat(forPath: dstParentPath)
        }
    }

    func link(target: NFSFileHandle, parent: NFSFileHandle, name: String) async throws {
        // fsaccess_mount 에 hardlink 가 없다.
        throw NFSError.notSupported
    }

    func readlink(handle: NFSFileHandle) async throws -> String {
        let (_, entry) = try await decodeHandle(handle)
        guard entry.kind == .hostFile,
              let mountSessionId = entry.mountSessionId,
              let hostFileId = entry.hostFileId else {
            throw NFSError.notSupported
        }
        let channel = try await channel(for: mountSessionId)
        let path = await channel.pathMap.path(forHostHandleId: hostFileId)
        let response = try await channel.sendStat(path: path, followSymlinks: false)
        guard response.success, let target = response.stat?.symlinkTarget else {
            if response.success { throw NFSError.invalid }
            throw Self.nfsError(from: response.error)
        }
        return target
    }

    // MARK: - OPEN / CLOSE

    /// host-internal entry id + per-channel monotonic counter 로 unique 한
    /// stateid 의 12-byte ``other`` 를 발급. 같은 hostFile 에 여러 OPEN 이
    /// 떨어져도 stateid 가 unique 하므로 (RFC 7530 §8.1.3 정합), CLOSE 가 자기
    /// stateid 의 slot 만 정확히 닫을 수 있다. NFSv4 client 일부가 OPEN 응답에
    /// ``NFSStateID.bypass`` (all-ones) 가 오면 fh 를 즉시 retire 하므로 정상
    /// stateid 가 필요.
    private static func issueStateid(forEntryId entryId: UInt64, counter: UInt32) -> NFSStateID {
        var other = HandleTable.encode(entryId)  // 8 bytes
        var beCounter = counter.bigEndian
        let counterBytes = withUnsafeBytes(of: &beCounter) { Data($0) }
        other.append(counterBytes)  // 12 bytes 총합
        return NFSStateID(seqid: 1, other: other)
    }

    /// stateid 가 RFC 7530 §8.1.4.2 의 anonymous (all-zero) 인지 판단.
    private static func isAnonymous(_ stateid: NFSStateID) -> Bool {
        return stateid.seqid == 0 && stateid.other.allSatisfy { $0 == 0 }
    }

    func open(parent: NFSFileHandle, name: String,
              share: NFSShareAccess, deny: NFSShareDeny,
              owner: NFSOpenOwner,
              wantDelegation: NFSDelegationHint,
              create: NFSCreateMode) async throws -> (handle: NFSFileHandle, result: NFSOpenResult) {
        let (_, parentEntry) = try await decodeHandle(parent)
        // _README.txt 는 root 의 read-only 파일. virtual entry 라 navigator
        // 측 OpenSlot 등록은 불필요 — read 경로가 entry.kind 분기로 자체 처리.
        if parentEntry.kind == .root, name == "_README.txt", await virtualTree.shouldShowReadme() {
            let fh = NFSFileHandle(HandleTable.encode(HandleTable.readmeEntryId))
            let stateid = Self.issueStateid(forEntryId: HandleTable.readmeEntryId, counter: 0)
            return (fh, NFSOpenResult(stateid: stateid, rflags: [], delegation: .none))
        }
        // .metadata_never_index 도 root 의 read-only sentinel.
        if parentEntry.kind == .root, name == Self.metadataNeverIndexName {
            let fh = NFSFileHandle(HandleTable.encode(HandleTable.metadataNeverIndexEntryId))
            let stateid = Self.issueStateid(forEntryId: HandleTable.metadataNeverIndexEntryId, counter: 0)
            return (fh, NFSOpenResult(stateid: stateid, rflags: [], delegation: .none))
        }
        let (mountSessionId, parentPath, connLabel) = try await mountContext(for: parentEntry)
        let channel = try await channel(for: mountSessionId)
        let childPath = joinPath(parent: parentPath, name: name)
        let accessMode: AccessMode
        let read = share.contains(.read)
        let write = share.contains(.write)
        if read && write { accessMode = .readWrite }
        else if write { accessMode = .write }
        else { accessMode = .read }
        // RFC 7530 §16.16 NFSCreateMode → fsaccess_mount CreateDisposition.
        //   .open                  → openExisting (NOCREATE)
        //   .create(attrs)         → openOrCreate (UNCHECKED4 / GUARDED4 — nanonfs
        //                            는 두 mode 를 합쳐서 .create 로 줌. GUARDED4 의
        //                            "이미 존재하면 EXIST" 의미는 보존되지 않음.)
        //   .createExclusive       → createNew    (EXCLUSIVE4)
        let disposition: CreateDisposition
        let createMode: UInt32
        switch create {
        case .open:
            disposition = .openExisting
            createMode = 0
        case .create(let attrs):
            disposition = .openOrCreate
            createMode = attrs.mode ?? 0o644
        case .createExclusive:
            disposition = .createNew
            createMode = 0o644
        }
        let response = try await channel.sendOpen(
            path: childPath, accessMode: accessMode,
            createDisposition: disposition, flags: [], mode: createMode
        )
        guard response.success else {
            logger.error("open: navigator returned success=false for path=\(childPath) disposition=\(String(describing: disposition)): \(response.error?.message ?? "<no info>")")
            throw Self.nfsError(from: response.error)
        }
        // 파일이 새로 생성됐을 가능성이 있는 경로면 parent dirent 캐시 invalidate.
        if disposition != .openExisting {
            await channel.pathMap.invalidateStat(forPath: parentPath)
        }
        let hostId = await channel.pathMap.issueIfAbsent(path: childPath)
        let newEntry = HandleEntry(
            kind: .hostFile, connectionLabel: connLabel,
            mountSessionId: mountSessionId, hostFileId: hostId
        )
        let id = await handleTable.issueIfAbsent(
            newEntry,
            key: HandleTable.keyForHostFile(mountSessionId: mountSessionId, path: childPath)
        )
        let fh = NFSFileHandle(HandleTable.encode(id))
        // 매 OPEN 마다 unique stateid + 별도 OpenSlot. 같은 hostFile 에 read /
        // write 가 동시에 OPEN 돼도 각자 자기 navHandle 을 보존 → CLOSE 가 자기
        // slot 만 닫고 다른 OPEN 의 navHandle 을 건드리지 않음.
        let counter = await channel.stateidGenerator.issue()
        let stateid = Self.issueStateid(forEntryId: id, counter: counter)
        await channel.openSlotTable.register(FSAccessMountChannel.OpenSlot(
            stateidOther: stateid.other,
            hostFileId: hostId,
            navigatorHandleId: response.handleId,
            accessMode: accessMode
        ))
        logger.info("open: path=\(childPath) hostFileId=\(hostId) navHandle=\(response.handleId) entryId=\(id) counter=\(counter)")
        return (fh, NFSOpenResult(stateid: stateid, rflags: [], delegation: .none))
    }

    func openConfirm(handle: NFSFileHandle, stateid: NFSStateID, seqid: UInt32) async throws -> NFSStateID {
        // RFC 7530 §16.18: server SHOULD increment seqid by 1 on confirm.
        return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
    }

    func openDowngrade(handle: NFSFileHandle, stateid: NFSStateID, share: NFSShareAccess, deny: NFSShareDeny) async throws -> NFSStateID {
        return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
    }

    func close(handle: NFSFileHandle, stateid: NFSStateID) async throws {
        let (id, entry) = try await decodeHandle(handle)
        logger.info("close: enter id=\(id) kind=\(String(describing: entry.kind))")
        if entry.kind == .readme || entry.kind == .metadataNeverIndex { return }
        guard entry.kind == .hostFile,
              entry.mountSessionId != nil else {
            return  // virtual tree directory close 는 noop.
        }
        let channel = try await channel(for: entry.mountSessionId!)
        // stateid → OpenSlot lookup. 동일 hostFile 의 다른 OPEN 이 살아있어도
        // 그 slot 들은 절대 건드리지 않는다 (이전 워크어라운드의 race fix).
        guard let slot = await channel.openSlotTable.unregister(stateidOther: stateid.other) else {
            // Stale stateid: 이미 close 된 OPEN 이거나 client 가 anonymous /
            // bypass stateid 로 close 를 시도한 비정상 케이스. RFC 7530
            // §16.2.5 — close 는 정상 stateid 를 요구. silently noop 하지
            // 않고 명시적으로 staleStateid 환원해 client 가 정상화하게.
            logger.warning("close: stateid lookup miss — id=\(id) stateid=\(stateid.other.map { String(format: "%02x", $0) }.joined())")
            throw NFSError.staleStateid
        }
        let response = try await channel.sendClose(handleId: slot.navigatorHandleId)
        guard response.success else { throw Self.nfsError(from: response.error) }
        // pathMap.Record 자체는 보존 — 같은 fh 를 재 OPEN 할 때 hostId 가 stable
        // 해야 NFS client cache 가 깨지지 않는다.
    }

    // MARK: - I/O

    func read(handle: NFSFileHandle, stateid: NFSStateID, offset: UInt64, count: Int) async throws -> NFSReadResult {
        let (id, entry) = try await decodeHandle(handle)
        // logger.info("read: enter id=\(id) kind=\(String(describing: entry.kind)) offset=\(offset) count=\(count)")
        if entry.kind == .readme {
            let body = Self.readmeBody.data(using: .utf8) ?? Data()
            if offset >= UInt64(body.count) { return NFSReadResult(data: Data(), eof: true) }
            let start = Int(offset)
            let end = min(body.count, start + count)
            return NFSReadResult(data: body.subdata(in: start..<end), eof: end >= body.count)
        }
        if entry.kind == .metadataNeverIndex {
            // 0-byte sentinel — Spotlight 가 stat() 만 보지만 read() 도 던질 수 있음.
            return NFSReadResult(data: Data(), eof: true)
        }
        guard entry.kind == .hostFile,
              let mountSessionId = entry.mountSessionId,
              let hostFileId = entry.hostFileId else {
            logger.error("read: not a hostFile — id=\(id) kind=\(String(describing: entry.kind))")
            throw NFSError.isDirectory
        }
        let channel = try await channel(for: mountSessionId)
        // stateid resolution: anonymous (RFC 7530 §8.1.4.2) 면 hostFile 의
        // bestSlot 으로 fallback, 그 외 stateid 는 정확한 slot lookup 요구.
        // (write 와 다르게 read 는 RFC 가 anonymous 를 허용한다.)
        let navHandle: UInt64
        if Self.isAnonymous(stateid) {
            guard let slot = await channel.openSlotTable.bestSlot(forHostFileId: hostFileId) else {
                logger.error("read: anonymous stateid but no OPEN slot for hostFileId=\(hostFileId)")
                throw NFSError.badStateid
            }
            navHandle = slot.navigatorHandleId
        } else {
            guard let slot = await channel.openSlotTable.lookup(stateidOther: stateid.other) else {
                logger.error("read: stateid lookup miss — id=\(id) hostFileId=\(hostFileId)")
                throw NFSError.staleStateid
            }
            navHandle = slot.navigatorHandleId
        }
        let response = try await channel.sendRead(
            handleId: navHandle, offset: offset, length: UInt32(min(count, Int(UInt32.max)))
        )
        guard response.success else { throw Self.nfsError(from: response.error) }
        // mount session 이 zstd 협상 상태면 wire bytes 를 decompress 하고 NFS client 에게 raw 반환.
        let payload: Data
        if channel.selectedCompressionMethod == .zstd {
            do {
                payload = try ZstdCodec.decompress(response.data)
            } catch {
                logger.error("read: zstd decompression failed: \(error)")
                throw NFSError.io
            }
        } else {
            payload = response.data
        }
        return NFSReadResult(data: payload, eof: response.isEof)
    }

    func write(handle: NFSFileHandle, stateid: NFSStateID, offset: UInt64, stability: NFSWriteStability, data: Data) async throws -> NFSWriteResult {
        let (_, entry) = try await decodeHandle(handle)
        guard entry.kind == .hostFile,
              let mountSessionId = entry.mountSessionId,
              let hostFileId = entry.hostFileId else {
            throw NFSError.readOnly
        }
        let channel = try await channel(for: mountSessionId)
        // write 는 RFC 7530 §8.1.4.2 에 따라 anonymous stateid 가 허용되지
        // 않는다 (§8.1.4 의 special stateid 는 read-only). 정확한 slot
        // lookup 만 인정.
        if Self.isAnonymous(stateid) {
            logger.error("write: anonymous stateid not permitted (RFC 7530 §8.1.4.2)")
            throw NFSError.badStateid
        }
        guard let slot = await channel.openSlotTable.lookup(stateidOther: stateid.other) else {
            logger.error("write: stateid lookup miss — hostFileId=\(hostFileId)")
            throw NFSError.staleStateid
        }
        let navHandle = slot.navigatorHandleId
        // mount session 이 zstd 협상 상태면 NFS client 가 준 raw 바이트를 wire 로
        // 보내기 전 zstd 압축. response.bytesWritten 은 navigator 가 *uncompressed*
        // 바이트 단위로 응답해야 spec 일관성 — 이는 navigator 측 책임.
        let wireData: Data
        if channel.selectedCompressionMethod == .zstd {
            do {
                wireData = try ZstdCodec.compress(data)
            } catch {
                logger.error("write: zstd compression failed: \(error)")
                throw NFSError.io
            }
        } else {
            wireData = data
        }
        let response = try await channel.sendWrite(handleId: navHandle, offset: offset, data: wireData)
        guard response.success else { throw Self.nfsError(from: response.error) }
        // size / mtime 변경 → 캐시된 stat invalidate.
        await channel.pathMap.invalidateStat(forHostHandleId: hostFileId)
        return NFSWriteResult(count: Int(response.bytesWritten), committed: stability, writeVerifier: 0)
    }

    func commit(handle: NFSFileHandle, offset: UInt64, count: UInt64) async throws -> UInt64 {
        let (_, entry) = try await decodeHandle(handle)
        guard entry.kind == .hostFile,
              let mountSessionId = entry.mountSessionId,
              let hostFileId = entry.hostFileId else {
            return 0
        }
        let channel = try await channel(for: mountSessionId)
        // NFSv4 COMMIT 은 stateid 가 없는 op (RFC 7530 §16.6) — hostFile 단위로
        // 가장 강한 OPEN slot 을 골라 그 navHandle 로 flush. write OPEN 이
        // 살아있는 기간에 대한 commit 은 항상 그 navHandle 을 hit.
        guard let slot = await channel.openSlotTable.bestSlot(forHostFileId: hostFileId) else {
            // 어떤 OPEN 도 없는 상태에서 commit 이 들어오는 건 이상하지만,
            // POSIX 의 close-then-fsync 같은 흐름과 NFSv4 의 timing 차이로
            // 가능. 무해한 noop 으로 처리.
            return 0
        }
        let response = try await channel.sendFlush(handleId: slot.navigatorHandleId)
        guard response.success else { throw Self.nfsError(from: response.error) }
        return 0
    }

    // MARK: - Locking
    //
    // NFSv4 LOCK / LOCKT / LOCKU 를 mount session 의 supportsLocks capability
    // 에 따라 두 가지 경로로 분기한다.
    //
    // - `supportsLocks == false` (예: iOS navigator): NFS4ERR_NOTSUPP 로 환원하면
    //   QuickTime 같은 까다로운 client 가 read 시작도 못 하므로, 종전대로
    //   '잡힌 척' 응답 (fake success / lockTest=granted / unlock=success).
    // - `supportsLocks == true` (예: macOS navigator): fsaccess_mount channel
    //   로 dispatch 해서 navigator host OS 의 byte-range lock 으로 매핑한다.
    //
    // stateid 는 RFC 7530 §8.1.5 에 따라 echo + seqid 증가.

    private static func lockType(from nfs: NFSLockType) -> LockType {
        switch nfs {
        case .readShared, .readSharedBlocking: return .shared
        case .writeExclusive, .writeExclusiveBlocking: return .exclusive
        }
    }

    /// fsaccess `LockType` → NFS `NFSLockType` (LOCKT denied 응답에서 사용).
    /// 차단 variant 정보는 wire 에 없으므로 non-blocking 으로 환원한다.
    private static func nfsLockType(from fsa: LockType) -> NFSLockType {
        return fsa == .exclusive ? .writeExclusive : .readShared
    }

    /// hostFile entry 에서 (channel, navigatorHandleId, supportsLocks) 추출.
    /// stale 한 stateid / record 는 staleStateid / badHandle 로 매핑.
    /// `supportsLocks` 는 navigator 의 capability 광고와 host 측의 useFakeLocks
    /// 정책을 함께 반영한 effective 값. useFakeLocks=true 면 강제 false 로 다운
    /// 그레이드되어 lock callback 이 fake success 로 떨어진다.
    /// `stateid` 가 nil 이면 (LOCKT — RFC 7530 §16.11) hostFile 의 bestSlot 으로
    /// fallback 한다.
    private func resolveLockTarget(_ handle: NFSFileHandle, stateid: NFSStateID?) async throws -> (FSAccessMountChannel, UInt64, Bool) {
        let (_, entry) = try await decodeHandle(handle)
        guard entry.kind == .hostFile,
              let mountSessionId = entry.mountSessionId,
              let hostFileId = entry.hostFileId else {
            throw NFSError.badHandle
        }
        let channel = try await channel(for: mountSessionId)
        let navHandle: UInt64
        if let stateid {
            if Self.isAnonymous(stateid) {
                logger.error("lock op: anonymous stateid not permitted")
                throw NFSError.badStateid
            }
            guard let slot = await channel.openSlotTable.lookup(stateidOther: stateid.other) else {
                logger.error("lock op: stateid lookup miss — hostFileId=\(hostFileId)")
                throw NFSError.staleStateid
            }
            navHandle = slot.navigatorHandleId
        } else {
            guard let slot = await channel.openSlotTable.bestSlot(forHostFileId: hostFileId) else {
                throw NFSError.badHandle
            }
            navHandle = slot.navigatorHandleId
        }
        let useFakeLocks = await NocFSAccessHost.shared.useFakeLocks
        let effectiveSupportsLocks = channel.supportsLocks && !useFakeLocks
        return (channel, navHandle, effectiveSupportsLocks)
    }

    func lock(handle: NFSFileHandle, type: NFSLockType, range: NFSLockRange, owner: NFSLockOwner, reclaim: Bool, stateid: NFSStateID) async throws -> NFSStateID {
        let (channel, navHandle, supportsLocks) = try await resolveLockTarget(handle, stateid: stateid)
        if !supportsLocks {
            return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
        }
        let response = try await channel.sendLock(
            handleId: navHandle,
            type: Self.lockType(from: type),
            offset: range.offset,
            length: range.length
        )
        if !response.success {
            // navigator 가 supportsLocks=true 라고 광고했음에도 notSupported 를
            // 반환한 비정상 케이스: 안전하게 fake success 로 fallback (client
            // 가 read 시작도 못 하는 사태 회피).
            if response.error?.code == .notSupported {
                logger.warning("fsaccess: navigator advertised supportsLocks=true but returned notSupported on Lock — falling back to fake success")
                return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
            }
            if response.error?.code == .wouldBlock {
                throw NFSError.lockDenied(conflict: range, type: type, owner: owner)
            }
            throw Self.nfsError(from: response.error)
        }
        return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
    }

    func lockTest(handle: NFSFileHandle, type: NFSLockType, range: NFSLockRange, owner: NFSLockOwner) async throws -> NFSLockTestResult {
        // LOCKT 는 stateid 가 없는 op — bestSlot fallback.
        let (channel, navHandle, supportsLocks) = try await resolveLockTarget(handle, stateid: nil)
        if !supportsLocks {
            return NFSLockTestResult(outcome: .granted)
        }
        let response = try await channel.sendTestLock(
            handleId: navHandle,
            type: Self.lockType(from: type),
            offset: range.offset,
            length: range.length
        )
        if !response.success {
            if response.error?.code == .notSupported {
                return NFSLockTestResult(outcome: .granted)
            }
            throw Self.nfsError(from: response.error)
        }
        if response.canAcquire {
            return NFSLockTestResult(outcome: .granted)
        }
        let conflictRange = NFSLockRange(offset: response.conflictingOffset, length: response.conflictingLength)
        let conflictType = Self.nfsLockType(from: response.conflictingType)
        return NFSLockTestResult(outcome: .denied(conflict: conflictRange, type: conflictType, owner: owner))
    }

    func unlock(handle: NFSFileHandle, range: NFSLockRange, stateid: NFSStateID) async throws -> NFSStateID {
        let (channel, navHandle, supportsLocks) = try await resolveLockTarget(handle, stateid: stateid)
        if !supportsLocks {
            return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
        }
        let response = try await channel.sendUnlock(
            handleId: navHandle,
            offset: range.offset,
            length: range.length
        )
        if !response.success {
            if response.error?.code == .notSupported {
                return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
            }
            throw Self.nfsError(from: response.error)
        }
        return NFSStateID(seqid: stateid.seqid &+ 1, other: stateid.other)
    }

    // MARK: - Mount context resolution

    /// `(mountSessionId, parentPath, connectionLabel)` 추출 helper. parent 가
    /// `.mountSession` 이면 path = "/" (mount root), `.hostFile` 이면 그 경로.
    private func mountContext(for entry: HandleEntry) async throws -> (UUID, String, String?) {
        switch entry.kind {
        case .mountSession:
            guard let mountSessionId = entry.mountSessionId else { throw NFSError.badHandle }
            return (mountSessionId, "/", entry.connectionLabel)
        case .hostFile:
            guard let mountSessionId = entry.mountSessionId,
                  let hostFileId = entry.hostFileId else { throw NFSError.badHandle }
            let channel = try await channel(for: mountSessionId)
            let path = await channel.pathMap.path(forHostHandleId: hostFileId)
            return (mountSessionId, path.isEmpty ? "/" : path, entry.connectionLabel)
        default:
            throw NFSError.notDirectory
        }
    }
}
