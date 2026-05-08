//
//  FSAccessMountChannel.swift
//  NoctilucaServer
//
//  fsaccess_mount data channel — consuming peer (host) 측 구현.
//  See: docs/nocfsaccessd.md, SiriusProtocol/v1/channels/fsaccess_mount.mdproto.md
//
//  채널 lifecycle / handleFrame dispatch 외에 본 파일의 핵심 자료구조는 두 종류:
//  - ``MountSessionPathMap``: host-side hostFileId ↔ navigator-side path 매핑 +
//    path 별 stat 캐시.
//  - ``OpenSlotTable``: NFSv4 stateid ↔ navigator-side fsaccess_mount handleId
//    매핑. 같은 hostFile 의 read OPEN + write OPEN 이 동시에 살아있을 때 각자
//    별도 slot 으로 보존되어, CLOSE 가 자기 stateid 의 slot 만 정확히 닫고
//    다른 OPEN 의 navigator handle 은 건드리지 않는다.
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
    case lock(FileSystemLockResponse)
    case unlock(FileSystemUnlockResponse)
    case testLock(FileSystemTestLockResponse)
}

// MARK: - FSAccessMountChannel

final class FSAccessMountChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    let logger = NoctilucaLogger(category: "FSAccessMountChannel")

    private static let defaultServiceClass: ServiceClass = .signaling

    /// 본 mount channel 이 묶여있는 세션 id (`FileSystemMountResponse.sessionId`).
    let sessionId: UUID

    /// `FileSystemMountResponse.supportsLocks` capability. NFS LOCK / LOCKT /
    /// LOCKU callback 의 wire dispatch 여부를 결정한다 — true 면 wire 로
    /// 보내고, false 면 host 측에서 fake success 로 시뮬레이션. mount channel
    /// 생성 직후 control channel 측에서 1회 set 하며 그 이후로는 read-only.
    nonisolated(unsafe) var supportsLocks: Bool = false

    /// `FileSystemMountResponse.selectedCompressionMethod`. inline read/write 의
    /// data 필드와 stream IO 가 spawn 하는 transfer channel 의 transferArgs
    /// `compress=` 토큰에 그대로 사용된다. mount channel 생성 직후 1회 set
    /// 그 이후로는 read-only.
    nonisolated(unsafe) var selectedCompressionMethod: CompressionMethod = .none

    /// 응답 매칭. requestId → continuation.
    let pending = PendingMountReplies()

    /// requestId 발급기 (channel 단위 monotonic).
    let requestIds = RequestIdGenerator()

    /// host-side fsaccess_mount handleId ↔ navigator-side path 매핑. mount root
    /// 는 sentinel (`0`) 으로 표현한다.
    let pathMap = MountSessionPathMap()

    /// NFSv4 stateid → navigator-side fsaccess_mount handleId 매핑. open 마다
    /// unique 한 slot 이 발급된다 (같은 hostFile 의 read + write 동시 OPEN 이
    /// 별도 slot 으로 보존되어, close 가 stateid 만 보고 정확히 자기 slot 만
    /// 닫게 한다).
    let openSlotTable = OpenSlotTable()

    /// NFSv4 stateid 의 lower 4 byte counter. channel 단위 monotonic.
    let stateidGenerator = StateidGenerator()

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

        /// path 별 stat 캐시 TTL. Finder / Spotlight 가 같은 entry 의 GETATTR /
        /// LOOKUP 을 초당 수십\~수백 번 던지는 케이스에서 navigator wire RTT 를
        /// 흡수한다. 너무 길면 navigator 측 외부 변경의 반영 지연 (delete /
        /// truncate 등) 이 커지므로 짧게 유지.
        static let statCacheTTL: Duration = .seconds(2)

        /// hostFileId 가 가리키는 path + 캐시된 stat. navigator-side handleId 는
        /// ``OpenSlotTable`` 이 stateid 별로 따로 보관하므로 여기엔 두지 않는다.
        struct Record: Sendable {
            var path: String
            /// 직전 readdir / stat / fstat 응답으로 받은 navigator-side stat.
            /// `cachedStatExpiresAt` 가 future 일 때만 valid.
            var cachedStat: FileStat?
            var cachedStatExpiresAt: ContinuousClock.Instant?
        }

        private var records: [UInt64: Record] = [:]
        private var nextId: UInt64 = 1
        /// path → hostId 역방향 매핑. 같은 path 에 대해 같은 hostId 재사용
        /// (NFS client 가 fh 를 cache 하므로 fh 가 stable 해야 ESTALE 회피).
        private var idByPath: [String: UInt64] = [:]

        func issue(path: String) -> UInt64 {
            let id = nextId
            nextId &+= 1
            if nextId == 0 || nextId == Self.rootSentinel { nextId = 1 }
            records[id] = Record(path: path)
            idByPath[path] = id
            return id
        }

        /// 같은 path 가 이미 등록됐으면 기존 hostId 재사용. 없으면 새로 발급.
        func issueIfAbsent(path: String) -> UInt64 {
            if let existing = idByPath[path] { return existing }
            return issue(path: path)
        }

        func record(forHostHandleId id: UInt64) -> Record? {
            if id == Self.rootSentinel {
                return Record(path: "")
            }
            return records[id]
        }

        func path(forHostHandleId id: UInt64) -> String {
            if id == Self.rootSentinel { return "" }
            return records[id]?.path ?? ""
        }

        // MARK: - Stat cache

        /// 캐시된 stat 이 아직 유효 (now 이전 만료 X) 하면 리턴, 아니면 nil.
        func cachedStat(forHostHandleId id: UInt64) -> FileStat? {
            guard id != Self.rootSentinel,
                  let r = records[id],
                  let stat = r.cachedStat,
                  let exp = r.cachedStatExpiresAt,
                  exp > ContinuousClock.now else {
                return nil
            }
            return stat
        }

        /// path 로 캐시 조회. 같은 mount 내 lookup 직전 빠른 경로용.
        func cachedStat(forPath path: String) -> FileStat? {
            guard let id = idByPath[path] else { return nil }
            return cachedStat(forHostHandleId: id)
        }

        /// hostId 가 이미 존재할 때만 캐시 채움. 존재 안 하면 noop.
        func updateStat(forHostHandleId id: UInt64, stat: FileStat) {
            guard id != Self.rootSentinel, records[id] != nil else { return }
            records[id]?.cachedStat = stat
            records[id]?.cachedStatExpiresAt = ContinuousClock.now.advanced(by: Self.statCacheTTL)
        }

        /// path 가 이미 등록돼 있으면 캐시 채움. 없으면 새 hostId 발급해 채움.
        @discardableResult
        func issueIfAbsent(path: String, withStat stat: FileStat) -> UInt64 {
            let id = idByPath[path] ?? issue(path: path)
            records[id]?.cachedStat = stat
            records[id]?.cachedStatExpiresAt = ContinuousClock.now.advanced(by: Self.statCacheTTL)
            return id
        }

        func invalidateStat(forHostHandleId id: UInt64) {
            guard id != Self.rootSentinel else { return }
            records[id]?.cachedStat = nil
            records[id]?.cachedStatExpiresAt = nil
        }

        func invalidateStat(forPath path: String) {
            guard let id = idByPath[path] else { return }
            records[id]?.cachedStat = nil
            records[id]?.cachedStatExpiresAt = nil
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

    // MARK: - OpenSlot table

    /// NFSv4 OPEN 한 건당 하나의 slot. ``stateidOther`` (12 bytes) 가 unique key.
    /// 같은 hostFile 에 여러 OPEN (예: read + write 동시 OPEN by 다른 NFSv4
    /// OPEN owner) 이 떨어져도 각자 별도 slot 으로 보존된다. CLOSE 는 자기
    /// stateid 의 slot 의 navigatorHandleId 만 닫고 나머지 slot 에는 영향 없음.
    struct OpenSlot: Sendable {
        let stateidOther: Data
        let hostFileId: UInt64
        let navigatorHandleId: UInt64
        let accessMode: AccessMode
    }

    actor OpenSlotTable {
        private var byStateID: [Data: OpenSlot] = [:]
        /// hostFileId → 그 hostFile 에 발급된 모든 OPEN 의 stateidOther 집합.
        /// stateid 가 anonymous 인 op (RFC 7530 §8.1.4.2) 의 fallback path 와
        /// stateid 인자가 없는 GETATTR fastpath 에서 best slot 선택용.
        private var byHostFileId: [UInt64: Set<Data>] = [:]

        func register(_ slot: OpenSlot) {
            byStateID[slot.stateidOther] = slot
            byHostFileId[slot.hostFileId, default: []].insert(slot.stateidOther)
        }

        func lookup(stateidOther: Data) -> OpenSlot? {
            return byStateID[stateidOther]
        }

        /// hostFile 에 등록된 OPEN slot 중 가장 강한 access mode 1개. accessRank:
        /// ``readWrite`` > ``write`` > ``read`` > 그 외. anonymous READ stateid
        /// 의 fallback (RFC 7530 §8.1.4.2) 과 stateid 가 없는 GETATTR 에서 사용.
        func bestSlot(forHostFileId hostFileId: UInt64) -> OpenSlot? {
            guard let stateids = byHostFileId[hostFileId], !stateids.isEmpty else { return nil }
            return stateids.compactMap { byStateID[$0] }
                .max { Self.accessRank($0.accessMode) < Self.accessRank($1.accessMode) }
        }

        func slots(forHostFileId hostFileId: UInt64) -> [OpenSlot] {
            guard let stateids = byHostFileId[hostFileId] else { return [] }
            return stateids.compactMap { byStateID[$0] }
        }

        @discardableResult
        func unregister(stateidOther: Data) -> OpenSlot? {
            guard let slot = byStateID.removeValue(forKey: stateidOther) else { return nil }
            if var set = byHostFileId[slot.hostFileId] {
                set.remove(stateidOther)
                if set.isEmpty {
                    byHostFileId.removeValue(forKey: slot.hostFileId)
                } else {
                    byHostFileId[slot.hostFileId] = set
                }
            }
            return slot
        }

        /// 모든 slot 을 unregister 하고 목록을 리턴. caller (mount session unmount
        /// / channel teardown) 가 navigator 측에 ``FSAccessMountChannel.sendClose``
        /// 를 best-effort 로 발송하는 데 사용.
        func drainAll() -> [OpenSlot] {
            let all = Array(byStateID.values)
            byStateID.removeAll()
            byHostFileId.removeAll()
            return all
        }

        private static func accessRank(_ mode: AccessMode) -> Int {
            switch mode {
            case .readWrite: return 3
            case .write: return 2
            case .read: return 1
            default: return 0
            }
        }
    }

    actor StateidGenerator {
        private var nextOpenInstance: UInt32 = 1
        /// channel 생애 동안 monotonic. 0 / `.max` 는 NFSv4 anonymous (all-zero) /
        /// bypass (all-FF) stateid 와의 표면적 충돌을 피하려고 보수적으로 reserve.
        func issue() -> UInt32 {
            let v = nextOpenInstance
            nextOpenInstance &+= 1
            if nextOpenInstance == 0 || nextOpenInstance == .max { nextOpenInstance = 1 }
            return v
        }
    }

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
        case .fileSystemLockResponse:
            let r = try FileSystemLockResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .lock(r))
        case .fileSystemUnlockResponse:
            let r = try FileSystemUnlockResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .unlock(r))
        case .fileSystemTestLockResponse:
            let r = try FileSystemTestLockResponse.fromProtobufBytes(frame.data)
            await pending.resolve(id: r.requestId, .testLock(r))

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
        // 남아있던 OpenSlot 메모리만 정리. 이 시점에서 channel 자체가 닫혀
        // navigator 에 sendClose 를 보내봤자 의미가 없다 (host-initiated 명시
        // unmount 흐름에서는 ``NocFSAccessHost.removeMountSession`` 이 channel
        // 이 살아있는 동안 best-effort sendClose 를 먼저 발송한다).
        let leftover = await openSlotTable.drainAll()
        if !leftover.isEmpty {
            logger.info("teardown: dropping \(leftover.count) leftover OpenSlot(s) (channel already closed; navigator side cleans up at mount session teardown)")
        }
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

    // MARK: - Byte-range locking

    /// 비-블로킹 try-lock. mdproto LOCK SEMANTICS 부록 참고.
    /// `length == 0xFFFFFFFFFFFFFFFF` 는 "from offset to EOF" sentinel.
    func sendLock(handleId: UInt64, type: LockType, offset: UInt64, length: UInt64) async throws -> FileSystemLockResponse {
        let id = await requestIds.issue()
        let req = FileSystemLockRequest(requestId: id, handleId: handleId, type: type, offset: offset, length: length)
        let reply = try await sendAndAwait(opcode: .fileSystemLockRequest, message: req, requestId: id)
        guard case .lock(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    /// `length == 0xFFFFFFFFFFFFFFFF` 는 "from offset to EOF" sentinel.
    /// not-held 범위 unlock 도 success 로 보고됨 (POSIX 와 일치).
    func sendUnlock(handleId: UInt64, offset: UInt64, length: UInt64) async throws -> FileSystemUnlockResponse {
        let id = await requestIds.issue()
        let req = FileSystemUnlockRequest(requestId: id, handleId: handleId, offset: offset, length: length)
        let reply = try await sendAndAwait(opcode: .fileSystemUnlockRequest, message: req, requestId: id)
        guard case .unlock(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }

    /// POSIX `fcntl(F_GETLK)` 등가물. 결과는 advisory.
    func sendTestLock(handleId: UInt64, type: LockType, offset: UInt64, length: UInt64) async throws -> FileSystemTestLockResponse {
        let id = await requestIds.issue()
        let req = FileSystemTestLockRequest(requestId: id, handleId: handleId, type: type, offset: offset, length: length)
        let reply = try await sendAndAwait(opcode: .fileSystemTestLockRequest, message: req, requestId: id)
        guard case .testLock(let response) = reply else { throw FSAccessChannelError.responseMismatch }
        return response
    }
}
