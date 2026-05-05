//
//  FSAccessMountChannel.swift
//  NoctilucaServer
//
//  fsaccess_mount data channel — consuming peer (host) 측 구현.
//  See: docs/nocfsaccessd.md, SiriusProtocol/v1/channels/fsaccess_mount.mdproto.md
//
//  본 파일의 Stage C 버전은 채널 lifecycle / handleFrame dispatch 의 *프레임워크*
//  만 잡는다. 모든 13개 message 의 발신 / 응답 매칭 본문은 Stage F 에서 본격
//  구현된다.
//

import Foundation

import SiriusKit

// MARK: - Reply unification

/// fsaccess_mount 의 모든 응답을 enum 으로 unification 해서 단일 typed
/// continuation 으로 매칭한다. 호출자는 자기가 원하는 case 만 unwrap.
enum FSAccessMountReply: Sendable {
    case open(FileSystemOpenResponse)
    case close(FileSystemCloseResponse)
    case read(FileSystemReadResponse)
    case write(FileSystemWriteResponse)
    case flush(FileSystemFlushResponse)
    case stat(FileSystemStatResponse)
    case fstat(FileSystemFStatResponse)
    case readdir(FileSystemReadDirResponse)
    case mkdir(FileSystemMkdirResponse)
    case rmdir(FileSystemRmdirResponse)
    case unlink(FileSystemUnlinkResponse)
    case rename(FileSystemRenameResponse)
    case ftruncate(FileSystemFTruncateResponse)
}

// MARK: - FSAccessMountChannel

final class FSAccessMountChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    let logger = NoctilucaLogger(category: "FSAccessMountChannel")

    private static let defaultServiceClass: ServiceClass = .signaling

    /// 본 mount channel 이 묶여있는 세션 id (`FileSystemMountResponse.sessionId`).
    let sessionId: UUID

    /// 응답 매칭. requestId → continuation.
    let pending = PendingMountReplies()

    /// requestId 발급기 (channel 단위 monotonic).
    let requestIds = RequestIdGenerator()

    /// host-side fsaccess_mount handleId ↔ navigator-side path 매핑. mount root
    /// 는 sentinel (`0`) 으로 표현한다.
    let pathMap = MountSessionPathMap()

    actor RequestIdGenerator {
        private var next: UInt64 = 1
        func issue() -> UInt64 {
            let v = next
            next &+= 1
            if next == 0 { next = 1 }
            return v
        }
    }

    actor MountSessionPathMap {
        /// mount root 의 sentinel host-side handleId.
        static let rootSentinel: UInt64 = 0

        struct Record: Sendable {
            var path: String
            /// fsaccess_mount.OPEN 응답에서 받은 navigator-side handleId. 아직
            /// open 안 된 entry (lookup 만 된 상태) 면 nil.
            var navigatorHandleId: UInt64?
        }

        private var records: [UInt64: Record] = [:]
        private var nextId: UInt64 = 1
        /// path → hostId 역방향 매핑. 같은 path 에 대해 같은 hostId 재사용
        /// (NFS client 가 fh 를 cache 하므로 fh 가 stable 해야 ESTALE 회피).
        private var idByPath: [String: UInt64] = [:]

        func issue(path: String, navigatorHandleId: UInt64? = nil) -> UInt64 {
            let id = nextId
            nextId &+= 1
            if nextId == 0 || nextId == Self.rootSentinel { nextId = 1 }
            records[id] = Record(path: path, navigatorHandleId: navigatorHandleId)
            idByPath[path] = id
            return id
        }

        /// 같은 path 가 이미 등록됐으면 기존 hostId 재사용. 없으면 새로 발급.
        func issueIfAbsent(path: String) -> UInt64 {
            if let existing = idByPath[path] { return existing }
            return issue(path: path)
        }

        func attachNavigatorHandle(hostId: UInt64, navigatorId: UInt64) {
            guard hostId != Self.rootSentinel else { return }
            records[hostId]?.navigatorHandleId = navigatorId
        }

        func record(forHostHandleId id: UInt64) -> Record? {
            if id == Self.rootSentinel {
                return Record(path: "", navigatorHandleId: nil)
            }
            return records[id]
        }

        func path(forHostHandleId id: UInt64) -> String {
            if id == Self.rootSentinel { return "" }
            return records[id]?.path ?? ""
        }

        /// host file 의 record 를 보존하면서 navigator-side handleId 만 떼어낸다.
        /// close 후 같은 fh 를 재 OPEN 할 때 같은 hostId 가 유지되어야 NFS
        /// client cache 가 깨지지 않는다.
        func detachNavigatorHandle(hostId: UInt64) {
            guard hostId != Self.rootSentinel else { return }
            records[hostId]?.navigatorHandleId = nil
        }

        @discardableResult
        func unregister(_ id: UInt64) -> Record? {
            guard id != Self.rootSentinel else { return nil }
            let removed = records.removeValue(forKey: id)
            if let path = removed?.path {
                idByPath.removeValue(forKey: path)
            }
            return removed
        }
    }

    actor PendingMountReplies {
        private var conts: [UInt64: CheckedContinuation<FSAccessMountReply, Error>] = [:]

        func register(id: UInt64, _ cont: CheckedContinuation<FSAccessMountReply, Error>) {
            conts[id] = cont
        }

        @discardableResult
        func resolve(id: UInt64, _ reply: FSAccessMountReply) -> Bool {
            guard let cont = conts.removeValue(forKey: id) else { return false }
            cont.resume(returning: reply)
            return true
        }

        @discardableResult
        func resolve(id: UInt64, error: Error) -> Bool {
            guard let cont = conts.removeValue(forKey: id) else { return false }
            cont.resume(throwing: error)
            return true
        }

        func failAll(_ error: Error) {
            for (_, cont) in conts { cont.resume(throwing: error) }
            conts.removeAll()
        }
    }

    nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<FSAccessMountChannel>!

    init(handle: ChannelHandle, sessionId: UUID) {
        self.handle = handle
        self.sessionId = sessionId
        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    /// ``Channel`` 프로토콜의 required initializer — 실 동작 경로에서는 사용되지
    /// 않습니다. ``NoctilucaFeatureProvider`` 는 항상 sessionId 가 있는
    /// designated initializer 를 호출합니다. 본 initializer 는 protocol 만족용.
    convenience init(handle: ChannelHandle) {
        assertionFailure("FSAccessMountChannel: sessionId-less initializer must not be used; pass sessionId via init(handle:sessionId:).")
        self.init(handle: handle, sessionId: UUID())
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
        await FSAccessRequestRouter.shared.register(self, for: self.sessionId)
        logger.info("FSAccessMountChannel ready: session=\(self.sessionId)")
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        // Stage F 에서 모든 *Response opcode 별 dispatch 가 들어온다. 현재는 단일
        // generic helper 로 매칭 가능한 응답만 처리.
        switch frame.opcode {
        case .fileSystemOpenResponse:
            let r = try FileSystemOpenResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .open(r))
        case .fileSystemCloseResponse:
            let r = try FileSystemCloseResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .close(r))
        case .fileSystemReadResponse:
            let r = try FileSystemReadResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .read(r))
        case .fileSystemWriteResponse:
            let r = try FileSystemWriteResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .write(r))
        case .fileSystemFlushResponse:
            let r = try FileSystemFlushResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .flush(r))
        case .fileSystemStatResponse:
            let r = try FileSystemStatResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .stat(r))
        case .fileSystemFStatResponse:
            let r = try FileSystemFStatResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .fstat(r))
        case .fileSystemReadDirResponse:
            let r = try FileSystemReadDirResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .readdir(r))
        case .fileSystemMkdirResponse:
            let r = try FileSystemMkdirResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .mkdir(r))
        case .fileSystemRmdirResponse:
            let r = try FileSystemRmdirResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .rmdir(r))
        case .fileSystemUnlinkResponse:
            let r = try FileSystemUnlinkResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .unlink(r))
        case .fileSystemRenameResponse:
            let r = try FileSystemRenameResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .rename(r))
        case .fileSystemFTruncateResponse:
            let r = try FileSystemFTruncateResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .ftruncate(r))

        default:
            logger.warning("Received unexpected opcode on host-side fsaccess_mount channel: \(frame.opcode)")
        }
    }

    func handleError(error: any Error) async {
        logger.error("FSAccessMountChannel stream error (session=\(self.sessionId)): \(error)")
        await teardown()
    }

    func handleStreamClose() async {
        logger.info("FSAccessMountChannel closed (session=\(self.sessionId)).")
        await teardown()
    }

    private func teardown() async {
        await FSAccessRequestRouter.shared.unregister(sessionId: self.sessionId)
        await pending.failAll(FSAccessChannelError.channelClosed)
    }

    // MARK: - Send helpers

    private func sendAndAwait(opcode: MessageOpcode,
                              message: any DecodableSiriusMessage,
                              requestId: UInt64) async throws -> FSAccessMountReply {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FSAccessMountReply, Error>) in
            Task {
                await pending.register(id: requestId, cont)
                do {
                    try await handle.send(opcode: opcode, message: message)
                } catch {
                    await pending.resolve(id: requestId, error: error)
                }
            }
        }
    }

    // MARK: - Public API (Stage F: Sirius ↔ XPC bridge 가 호출)

    func sendOpen(path: String,
                  accessMode: AccessMode,
                  createDisposition: CreateDisposition,
                  flags: OpenFlags,
                  mode: UInt32) async throws -> FileSystemOpenResponse {
        let id = await requestIds.issue()
        let req = FileSystemOpenRequest(
            requestId: id, path: path,
            accessMode: accessMode, createDisposition: createDisposition,
            flags: flags, mode: mode
        )
        let reply = try await sendAndAwait(opcode: .fileSystemOpenRequest, message: req, requestId: id)
        guard case .open(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendClose(handleId: UInt64) async throws -> FileSystemCloseResponse {
        let id = await requestIds.issue()
        let req = FileSystemCloseRequest(requestId: id, handleId: handleId)
        let reply = try await sendAndAwait(opcode: .fileSystemCloseRequest, message: req, requestId: id)
        guard case .close(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendRead(handleId: UInt64, offset: UInt64, length: UInt32) async throws -> FileSystemReadResponse {
        let id = await requestIds.issue()
        let req = FileSystemReadRequest(requestId: id, handleId: handleId, offset: offset, length: length)
        let reply = try await sendAndAwait(opcode: .fileSystemReadRequest, message: req, requestId: id)
        guard case .read(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendWrite(handleId: UInt64, offset: UInt64, data: Data) async throws -> FileSystemWriteResponse {
        let id = await requestIds.issue()
        let req = FileSystemWriteRequest(requestId: id, handleId: handleId, offset: offset, data: data)
        let reply = try await sendAndAwait(opcode: .fileSystemWriteRequest, message: req, requestId: id)
        guard case .write(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendFlush(handleId: UInt64) async throws -> FileSystemFlushResponse {
        let id = await requestIds.issue()
        let req = FileSystemFlushRequest(requestId: id, handleId: handleId)
        let reply = try await sendAndAwait(opcode: .fileSystemFlushRequest, message: req, requestId: id)
        guard case .flush(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendStat(path: String, followSymlinks: Bool) async throws -> FileSystemStatResponse {
        let id = await requestIds.issue()
        let req = FileSystemStatRequest(requestId: id, path: path, followSymlinks: followSymlinks)
        let reply = try await sendAndAwait(opcode: .fileSystemStatRequest, message: req, requestId: id)
        guard case .stat(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendFStat(handleId: UInt64) async throws -> FileSystemFStatResponse {
        let id = await requestIds.issue()
        let req = FileSystemFStatRequest(requestId: id, handleId: handleId)
        let reply = try await sendAndAwait(opcode: .fileSystemFStatRequest, message: req, requestId: id)
        guard case .fstat(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendReadDir(handleId: UInt64, maxEntries: UInt32) async throws -> FileSystemReadDirResponse {
        let id = await requestIds.issue()
        let req = FileSystemReadDirRequest(requestId: id, handleId: handleId, maxEntries: maxEntries)
        let reply = try await sendAndAwait(opcode: .fileSystemReadDirRequest, message: req, requestId: id)
        guard case .readdir(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendMkdir(path: String, mode: UInt32) async throws -> FileSystemMkdirResponse {
        let id = await requestIds.issue()
        let req = FileSystemMkdirRequest(requestId: id, path: path, mode: mode)
        let reply = try await sendAndAwait(opcode: .fileSystemMkdirRequest, message: req, requestId: id)
        guard case .mkdir(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendRmdir(path: String) async throws -> FileSystemRmdirResponse {
        let id = await requestIds.issue()
        let req = FileSystemRmdirRequest(requestId: id, path: path)
        let reply = try await sendAndAwait(opcode: .fileSystemRmdirRequest, message: req, requestId: id)
        guard case .rmdir(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendUnlink(path: String) async throws -> FileSystemUnlinkResponse {
        let id = await requestIds.issue()
        let req = FileSystemUnlinkRequest(requestId: id, path: path)
        let reply = try await sendAndAwait(opcode: .fileSystemUnlinkRequest, message: req, requestId: id)
        guard case .unlink(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendRename(oldPath: String, newPath: String) async throws -> FileSystemRenameResponse {
        let id = await requestIds.issue()
        let req = FileSystemRenameRequest(requestId: id, oldPath: oldPath, newPath: newPath)
        let reply = try await sendAndAwait(opcode: .fileSystemRenameRequest, message: req, requestId: id)
        guard case .rename(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    func sendFTruncate(handleId: UInt64, length: UInt64) async throws -> FileSystemFTruncateResponse {
        let id = await requestIds.issue()
        let req = FileSystemFTruncateRequest(requestId: id, handleId: handleId, length: length)
        let reply = try await sendAndAwait(opcode: .fileSystemFTruncateRequest, message: req, requestId: id)
        guard case .ftruncate(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }
}
