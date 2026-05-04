//
//  NocFSAccessHostXPCExport.swift
//  NoctilucaServer
//
//  ``NocFSAccessHostProtocol`` 의 NSObject 구현체. 데몬이 NFS callback 처리 중
//  reverse-XPC 로 호출하면 본 객체가 받아서 ``FSAccessRequestRouter`` 를 거쳐
//  적절한 ``FSAccessMountChannel`` 로 forward 한다.
//
//  Stage F: 13개 fsaccess_mount 메시지 발신 + 응답을 NocFSFileStat /
//  NocFSDirEntry 등 XPC DTO 로 변환해 데몬에 reply.
//

import Foundation

import SiriusKit

import NocFSAccessXPC

@objc final class NocFSAccessHostXPCExport: NSObject, NocFSAccessHostProtocol, @unchecked Sendable {
    private let logger = NoctilucaLogger(category: "NocFSAccessHostXPCExport")

    override init() {
        super.init()
    }

    // MARK: - Lookup helpers

    private func lookupChannel(_ mountSessionId: String) async -> FSAccessMountChannel? {
        guard let id = UUID(uuidString: mountSessionId) else { return nil }
        return await FSAccessRequestRouter.shared.channel(for: id)
    }

    /// (mountSessionId, parentHostHandleId, name) → joined path. parent 가 root
    /// sentinel(0) 이면 `/` 가 prefix 가 된다.
    private static func joinPath(parent: String, name: String) -> String {
        if parent.isEmpty || parent == "/" {
            return "/" + name
        }
        return parent + "/" + name
    }

    private static func makeFileStat(_ stat: FileStat) -> NocFSFileStat {
        return NocFSFileStat(
            type: stat.type.rawValue,
            size: stat.size,
            mode: stat.mode,
            mtimeMs: stat.mtimeMs,
            atimeMs: stat.atimeMs,
            btimeMs: stat.btimeMs,
            attributes: stat.attributes.rawValue,
            symlinkTarget: stat.symlinkTarget
        )
    }

    /// `FileStat?` 가 nil 이면 unknown type 으로 채운 placeholder 를 만든다.
    private static func makeFileStatOrPlaceholder(_ stat: FileStat?) -> NocFSFileStat {
        if let stat { return makeFileStat(stat) }
        return NocFSFileStat(
            type: FileType.unknown.rawValue,
            size: 0, mode: 0,
            mtimeMs: 0, atimeMs: 0, btimeMs: 0,
            attributes: 0, symlinkTarget: nil
        )
    }

    private static func nsErrorOrInternal(_ info: ErrorInfo?) -> NSError {
        if let info { return FSAccessErrorTranslator.toNSError(info) }
        return NSError.nocFSPosix(EIO, message: "fsaccess_mount returned success=false without ErrorInfo")
    }

    // MARK: - NocFSAccessHostProtocol

    func lookup(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(0, nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let parentPath = await channel.pathMap.path(forHostHandleId: parentHandleId)
            let childPath = Self.joinPath(parent: parentPath, name: name)
            do {
                let response = try await channel.sendStat(path: childPath, followSymlinks: false)
                if response.success, let stat = response.stat {
                    let newHostId = await channel.pathMap.issue(path: childPath)
                    reply(newHostId, Self.makeFileStat(stat), nil)
                } else {
                    reply(0, nil, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(0, nil, error as NSError)
            }
        }
    }

    func lookupParent(mountSessionId: String,
                      handleId: UInt64,
                      reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(0, nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let path = await channel.pathMap.path(forHostHandleId: handleId)
            // parent path 는 path 의 마지막 segment 를 떼어낸 것.
            let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
            let lastSlash = trimmed.lastIndex(of: "/")
            let parentPath = lastSlash.map { String(trimmed[..<$0]) } ?? ""
            do {
                let response = try await channel.sendStat(path: parentPath.isEmpty ? "/" : parentPath, followSymlinks: false)
                if response.success, let stat = response.stat {
                    let parentHostId = parentPath.isEmpty
                        ? FSAccessMountChannel.MountSessionPathMap.rootSentinel
                        : await channel.pathMap.issue(path: parentPath)
                    reply(parentHostId, Self.makeFileStat(stat), nil)
                } else {
                    reply(0, nil, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(0, nil, error as NSError)
            }
        }
    }

    func getattr(mountSessionId: String,
                 handleId: UInt64,
                 reply: @Sendable @escaping (NocFSFileStat?, Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            // 우선 navigator-side fsaccess_mount handleId 가 매핑되어 있으면 FStat,
            // 아니면 path 기반 Stat 으로 fallback.
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            do {
                let stat: FileStat?
                let errorInfo: ErrorInfo?
                let success: Bool
                if let navHandle = record?.navigatorHandleId {
                    let response = try await channel.sendFStat(handleId: navHandle)
                    success = response.success
                    stat = response.stat
                    errorInfo = response.error
                } else {
                    let path = record?.path ?? ""
                    let response = try await channel.sendStat(
                        path: path.isEmpty ? "/" : path, followSymlinks: true
                    )
                    success = response.success
                    stat = response.stat
                    errorInfo = response.error
                }
                if success, let stat {
                    reply(Self.makeFileStat(stat), nil)
                } else {
                    reply(nil, Self.nsErrorOrInternal(errorInfo))
                }
            } catch {
                reply(nil, error as NSError)
            }
        }
    }

    func setattr(mountSessionId: String,
                 handleId: UInt64,
                 patch: NocFSAttributesPatch,
                 reply: @Sendable @escaping (NocFSFileStat?, Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            // fsaccess_mount 는 setattr 가 없다. size 변경만 FTruncate 로 매핑하고,
            // 그 외 (mode / time) 는 best-effort 로 success 반환 (실제 적용 안 됨).
            if let sizeNumber = patch.size {
                let record = await channel.pathMap.record(forHostHandleId: handleId)
                guard let navHandle = record?.navigatorHandleId else {
                    reply(nil, NSError.nocFSPosix(EBADF))
                    return
                }
                do {
                    let response = try await channel.sendFTruncate(
                        handleId: navHandle, length: sizeNumber.uint64Value
                    )
                    if response.success {
                        // 그 후 stat 갱신.
                        let fstat = try await channel.sendFStat(handleId: navHandle)
                        if fstat.success, let stat = fstat.stat {
                            reply(Self.makeFileStat(stat), nil)
                        } else {
                            reply(nil, Self.nsErrorOrInternal(fstat.error))
                        }
                    } else {
                        reply(nil, Self.nsErrorOrInternal(response.error))
                    }
                } catch {
                    reply(nil, error as NSError)
                }
                return
            }
            // size 외 변경: best-effort 로 NOOP, getattr 결과 반환.
            do {
                let record = await channel.pathMap.record(forHostHandleId: handleId)
                let path = record?.path ?? "/"
                let response = try await channel.sendStat(path: path, followSymlinks: true)
                if response.success, let stat = response.stat {
                    reply(Self.makeFileStat(stat), nil)
                } else {
                    reply(nil, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(nil, error as NSError)
            }
        }
    }

    func access(mountSessionId: String,
                handleId: UInt64,
                mask: UInt32,
                reply: @Sendable @escaping (UInt32, Error?) -> Void) {
        // mask 그대로 echo. 실제 권한 검사는 navigator 가 read/write 시점에 한다.
        // mountSession 이 아예 없으면 ESTALE.
        Task {
            guard await self.lookupChannel(mountSessionId) != nil else {
                reply(0, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            reply(mask, nil)
        }
    }

    func readdir(mountSessionId: String,
                 handleId: UInt64,
                 cookie: UInt64,
                 cookieVerifier: UInt64,
                 maxEntries: Int,
                 reply: @Sendable @escaping ([NocFSDirEntry]?, Bool, UInt64, UInt64, Error?) -> Void) {
        _ = (cookie, cookieVerifier)
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(nil, true, 0, 0, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            // host 측 readdir 은 directory 의 path 를 OPEN(directoryOnly) 한 뒤
            // ReadDir(handleId) 로 진행. 단순화를 위해 path 조회 후 즉시 OPEN.
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            let path = record?.path ?? "/"
            do {
                let openResponse: FileSystemOpenResponse
                if let navHandle = record?.navigatorHandleId {
                    // 이미 열려 있는 directory handle 재사용.
                    openResponse = FileSystemOpenResponse(
                        requestId: 0, success: true, handleId: navHandle,
                        stat: FileStat(type: .directory, size: 0, mode: 0o755,
                                       mtimeMs: 0, atimeMs: 0, btimeMs: 0,
                                       attributes: [], symlinkTarget: nil, metadata: [:]),
                        error: nil
                    )
                } else {
                    openResponse = try await channel.sendOpen(
                        path: path,
                        accessMode: .read,
                        createDisposition: .openExisting,
                        flags: [.directoryOnly],
                        mode: 0
                    )
                    if openResponse.success {
                        await channel.pathMap.attachNavigatorHandle(
                            hostId: handleId, navigatorId: openResponse.handleId
                        )
                    }
                }
                guard openResponse.success else {
                    reply(nil, true, 0, 0, Self.nsErrorOrInternal(openResponse.error))
                    return
                }
                let response = try await channel.sendReadDir(
                    handleId: openResponse.handleId,
                    maxEntries: UInt32(min(maxEntries, Int(UInt32.max)))
                )
                if response.success {
                    var entries: [NocFSDirEntry] = []
                    for (i, entry) in response.entries.enumerated() {
                        let childPath = Self.joinPath(parent: path, name: entry.name)
                        let childHostId = await channel.pathMap.issue(path: childPath)
                        entries.append(NocFSDirEntry(
                            name: entry.name,
                            stat: Self.makeFileStatOrPlaceholder(entry.stat),
                            cookie: UInt64(i + 1),
                            handleId: childHostId
                        ))
                    }
                    reply(entries, response.isEnd, UInt64(entries.count), 0, nil)
                } else {
                    reply(nil, true, 0, 0, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(nil, true, 0, 0, error as NSError)
            }
        }
    }

    func readlink(mountSessionId: String,
                  handleId: UInt64,
                  reply: @Sendable @escaping (String?, Error?) -> Void) {
        // fsaccess_mount 는 readlink 가 따로 없다. Stat(followSymlinks=false) 에서
        // 받은 symlinkTarget 을 사용한다.
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            let path = record?.path ?? "/"
            do {
                let response = try await channel.sendStat(path: path, followSymlinks: false)
                if response.success, let target = response.stat?.symlinkTarget {
                    reply(target, nil)
                } else if response.success {
                    reply(nil, NSError.nocFSPosix(EINVAL, message: "not a symlink"))
                } else {
                    reply(nil, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(nil, error as NSError)
            }
        }
    }

    func open(mountSessionId: String,
              parentHandleId: UInt64,
              name: String,
              shareAccess: UInt32,
              shareDeny: UInt32,
              createMode: UInt32,
              reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        _ = (shareDeny)
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(0, nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let parentPath = await channel.pathMap.path(forHostHandleId: parentHandleId)
            let childPath = Self.joinPath(parent: parentPath, name: name)
            // shareAccess (NFSv4) → AccessMode.
            //   bit0 (READ) | bit1 (WRITE)
            let accessMode: AccessMode
            let read = (shareAccess & 0x1) != 0
            let write = (shareAccess & 0x2) != 0
            if read && write { accessMode = .readWrite }
            else if write { accessMode = .write }
            else { accessMode = .read }
            // createMode: NFSv4 OPEN4 createMode → CreateDisposition. 단순 매핑.
            let disposition: CreateDisposition
            switch createMode {
            case 0: disposition = .openExisting
            case 1: disposition = .createAlways
            case 2: disposition = .openOrCreate
            default: disposition = .openExisting
            }
            do {
                let response = try await channel.sendOpen(
                    path: childPath,
                    accessMode: accessMode,
                    createDisposition: disposition,
                    flags: [],
                    mode: 0o644
                )
                if response.success {
                    let hostId = await channel.pathMap.issue(
                        path: childPath, navigatorHandleId: response.handleId
                    )
                    reply(hostId, Self.makeFileStatOrPlaceholder(response.stat), nil)
                } else {
                    reply(0, nil, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(0, nil, error as NSError)
            }
        }
    }

    func close(mountSessionId: String,
               handleId: UInt64,
               reply: @Sendable @escaping (Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            // navigator handle 이 있으면 close 발신.
            if let navHandle = record?.navigatorHandleId {
                do {
                    let response = try await channel.sendClose(handleId: navHandle)
                    if !response.success {
                        reply(Self.nsErrorOrInternal(response.error))
                        return
                    }
                } catch {
                    reply(error as NSError)
                    return
                }
            }
            await channel.pathMap.unregister(handleId)
            reply(nil)
        }
    }

    func read(mountSessionId: String,
              handleId: UInt64,
              offset: UInt64,
              length: UInt32,
              reply: @Sendable @escaping (Data?, Bool, Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(nil, true, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            guard let navHandle = record?.navigatorHandleId else {
                reply(nil, true, NSError.nocFSPosix(EBADF))
                return
            }
            do {
                let response = try await channel.sendRead(
                    handleId: navHandle, offset: offset, length: length
                )
                if response.success {
                    reply(response.data, response.isEof, nil)
                } else {
                    reply(nil, true, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(nil, true, error as NSError)
            }
        }
    }

    func write(mountSessionId: String,
               handleId: UInt64,
               offset: UInt64,
               data: Data,
               stability: UInt32,
               reply: @Sendable @escaping (UInt32, Error?) -> Void) {
        _ = stability
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(0, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            guard let navHandle = record?.navigatorHandleId else {
                reply(0, NSError.nocFSPosix(EBADF))
                return
            }
            do {
                let response = try await channel.sendWrite(
                    handleId: navHandle, offset: offset, data: data
                )
                if response.success {
                    reply(response.bytesWritten, nil)
                } else {
                    reply(0, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(0, error as NSError)
            }
        }
    }

    func commit(mountSessionId: String,
                handleId: UInt64,
                offset: UInt64,
                length: UInt32,
                reply: @Sendable @escaping (Error?) -> Void) {
        _ = (offset, length)
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let record = await channel.pathMap.record(forHostHandleId: handleId)
            guard let navHandle = record?.navigatorHandleId else {
                reply(NSError.nocFSPosix(EBADF))
                return
            }
            do {
                let response = try await channel.sendFlush(handleId: navHandle)
                if response.success {
                    reply(nil)
                } else {
                    reply(Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(error as NSError)
            }
        }
    }

    func create(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                type: UInt32,
                attrs: NocFSAttributesInit,
                reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(0, nil, NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let parentPath = await channel.pathMap.path(forHostHandleId: parentHandleId)
            let childPath = Self.joinPath(parent: parentPath, name: name)
            do {
                if type == NocFSObjectType.directory.rawValue {
                    let response = try await channel.sendMkdir(path: childPath, mode: attrs.mode)
                    if response.success {
                        // 새로 생긴 dir 의 stat 을 stat 으로 fetch.
                        let stat = try await channel.sendStat(path: childPath, followSymlinks: false)
                        if stat.success, let s = stat.stat {
                            let hostId = await channel.pathMap.issue(path: childPath)
                            reply(hostId, Self.makeFileStat(s), nil)
                        } else {
                            reply(0, nil, Self.nsErrorOrInternal(stat.error))
                        }
                    } else {
                        reply(0, nil, Self.nsErrorOrInternal(response.error))
                    }
                    return
                }
                // regular file 또는 그 외 — Open(createNew) 으로 처리.
                let response = try await channel.sendOpen(
                    path: childPath,
                    accessMode: .readWrite,
                    createDisposition: .createNew,
                    flags: [],
                    mode: attrs.mode
                )
                if response.success {
                    let hostId = await channel.pathMap.issue(
                        path: childPath, navigatorHandleId: response.handleId
                    )
                    reply(hostId, Self.makeFileStatOrPlaceholder(response.stat), nil)
                } else {
                    reply(0, nil, Self.nsErrorOrInternal(response.error))
                }
            } catch {
                reply(0, nil, error as NSError)
            }
        }
    }

    func remove(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                reply: @Sendable @escaping (Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let parentPath = await channel.pathMap.path(forHostHandleId: parentHandleId)
            let childPath = Self.joinPath(parent: parentPath, name: name)
            // 우선 stat 으로 type 을 판별 후 dir 면 rmdir, 아니면 unlink.
            do {
                let stat = try await channel.sendStat(path: childPath, followSymlinks: false)
                guard stat.success, let s = stat.stat else {
                    reply(Self.nsErrorOrInternal(stat.error))
                    return
                }
                if s.type == .directory {
                    let response = try await channel.sendRmdir(path: childPath)
                    if response.success { reply(nil) }
                    else { reply(Self.nsErrorOrInternal(response.error)) }
                } else {
                    let response = try await channel.sendUnlink(path: childPath)
                    if response.success { reply(nil) }
                    else { reply(Self.nsErrorOrInternal(response.error)) }
                }
            } catch {
                reply(error as NSError)
            }
        }
    }

    func rename(mountSessionId: String,
                srcParentHandleId: UInt64,
                srcName: String,
                dstParentHandleId: UInt64,
                dstName: String,
                reply: @Sendable @escaping (Error?) -> Void) {
        Task {
            guard let channel = await self.lookupChannel(mountSessionId) else {
                reply(NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            let srcParent = await channel.pathMap.path(forHostHandleId: srcParentHandleId)
            let dstParent = await channel.pathMap.path(forHostHandleId: dstParentHandleId)
            let oldPath = Self.joinPath(parent: srcParent, name: srcName)
            let newPath = Self.joinPath(parent: dstParent, name: dstName)
            do {
                let response = try await channel.sendRename(oldPath: oldPath, newPath: newPath)
                if response.success { reply(nil) }
                else { reply(Self.nsErrorOrInternal(response.error)) }
            } catch {
                reply(error as NSError)
            }
        }
    }

    func link(mountSessionId: String,
              targetHandleId: UInt64,
              parentHandleId: UInt64,
              name: String,
              reply: @Sendable @escaping (Error?) -> Void) {
        // fsaccess_mount 에 hardlink 가 없다. ENOTSUP 환원.
        _ = (targetHandleId, parentHandleId, name)
        Task {
            guard await self.lookupChannel(mountSessionId) != nil else {
                reply(NSError.nocFSAccessXPC(.unknownMountSession))
                return
            }
            reply(NSError.nocFSPosix(ENOTSUP))
        }
    }
}
