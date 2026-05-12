//
//  FSAccessMountChannel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//
//  fsaccess_mount data channel — exposing peer 측 구현.
//  See: SiriusProtocol/v1/channels/fsaccess_mount.mdproto.md
//

import Foundation
import Darwin

import SiriusKitClient

// MARK: - Limits

private enum FSAccessMountLimits {
    /// `FileSystemReadRequest.length` / `FileSystemWriteRequest.data` 정상 상한.
    static let inlineBytesSpec = 1 * 1024 * 1024
    /// per-frame 하드 캡 — 초과 시 즉시 채널 종료.
    static let inlineBytesHard = 16 * 1024 * 1024
    /// `DirEntry.name` byte 길이 — 송신 측 self-cap.
    static let dirNameSpec = 255
    /// `ReadDirResponse.entries` count.
    static let dirEntriesSpec = 1024
    /// per-channel handle 상한.
    static let handlesSpec = 256
    static let handlesWarn = 384
    static let handlesHard = 8192
}

/// `FileSystemLockRequest.length` / `FileSystemUnlockRequest.length` /
/// `FileSystemTestLockRequest.length` 의 sentinel 값. mdproto 의
/// `LOCK SEMANTICS` 부록은 이 값을 "from offset to the maximum possible end of
/// file" 로 정의하며, host syscall 계층에서는 POSIX `l_len = 0` 으로 변환한다.
private let kFSAccessLockLengthSentinel: UInt64 = 0xFFFF_FFFF_FFFF_FFFF

/// 모든 `open(2)` 호출에 default 로 OR 되는 추가 플래그. macOS 에서는
/// `O_NOFOLLOW_ANY` (macOS 11+) 를 박아 *경로상의 어떤 component 도* symlink 면
/// open 을 거절하게 한다 — `FSAccessPathValidator` 의 lexical/realpath 사전
/// 검증과 함께 TOCTOU race 도 봉쇄. mdproto §"Symlinks" 의
/// "outside-the-subtree symlink MUST NOT be followed" 강제용.
///
/// iOS 는 byte-range lock 자체가 supportsLocks=false 인 것과 같은 이유 (sandbox
/// 가 컨테이너 밖 follow 를 이미 차단) 로 추가 플래그 불필요.
private let kFSAccessOpenExtraFlags: Int32 = {
#if os(macOS)
    return O_NOFOLLOW_ANY
#else
    return 0
#endif
}()

// MARK: - FSAccessMountChannel

final class FSAccessMountChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    let logger = NoctilucaLogger(category: "FSAccessMountChannel")

    /// 이 mount channel 이 바인딩된 mount session.
    /// `createIfAccepts` 에서 검증 후 주입.
    let mountSession: FSAccessMountSession

    private static let defaultServiceClass: ServiceClass = .background

    private let state = State()

    actor State {
        var handles: [UInt64: FSAccessHandle] = [:]
        var nextHandleId: UInt64 = 1

        /// `handleFrame` 이 spawn 한 in-flight dispatch task counter.
        /// teardown 시점에 drain 하여, fd close 가 진행중 syscall 보다 먼저
        /// 일어나서 stale fd 를 사용하는 use-after-close race 를 막는다.
        private var inFlightFrameCount: Int = 0
        private var drainContinuations: [CheckedContinuation<Void, Never>] = []

        func issueHandle(_ make: (UInt64) -> FSAccessHandle) -> FSAccessHandle {
            let id = nextHandleId
            nextHandleId &+= 1
            let handle = make(id)
            handles[id] = handle
            return handle
        }

        func get(_ id: UInt64) -> FSAccessHandle? {
            return handles[id]
        }

        func remove(_ id: UInt64) -> FSAccessHandle? {
            return handles.removeValue(forKey: id)
        }

        func count() -> Int {
            return handles.count
        }

        func snapshot() -> [FSAccessHandle] {
            return Array(handles.values)
        }

        func taskStarted() {
            inFlightFrameCount += 1
        }

        func taskFinished() {
            inFlightFrameCount -= 1
            if inFlightFrameCount == 0 {
                let conts = drainContinuations
                drainContinuations.removeAll()
                for c in conts { c.resume() }
            }
        }

        func waitForDrain() async {
            if inFlightFrameCount == 0 { return }
            await withCheckedContinuation { c in
                drainContinuations.append(c)
            }
        }
    }

    nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<FSAccessMountChannel>!

    init(handle: ChannelHandle, mountSession: FSAccessMountSession) {
        self.handle = handle
        self.mountSession = mountSession
        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    /// `Channel` 프로토콜의 init(handle:) 요구사항 만족용. 직접 사용 금지.
    /// 실제 인스턴스화는 `createIfAccepts(handle:args:clientSession:)` 를 통해서만.
    convenience init(handle: ChannelHandle) {
        fatalError("FSAccessMountChannel must be created via createIfAccepts(handle:args:clientSession:)")
    }

    /// args[0] 의 sessionId 가 활성 mount session 과 매칭되면 채널을 생성한다.
    /// 매칭 실패 시 nil 반환 → ChannelStartResponse(success=false).
    static func createIfAccepts(
        handle: ChannelHandle,
        args: [String],
        client: NoctilucaClient
    ) async -> FSAccessMountChannel? {
        guard handle.direction == .remote else {
            return nil
        }
        guard let sessionIdString = args.first,
              let sessionId = UUID(uuidString: sessionIdString) else {
            return nil
        }
        guard let mountSession = await MainActor.run(body: { client.fsAccessRemoteSession?.fsAccessMountSession(forId: sessionId) }) else {
            return nil
        }

        let channel = FSAccessMountChannel(handle: handle, mountSession: mountSession)
        mountSession.setMountChannel(channel)
        return channel
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        // counter 증가는 Task spawn 전에 수행 — Task 가 schedule 만 되고 아직
        // 실행 전인 상태에서 teardown 의 drain 이 통과해버리는 race 차단.
        // capturedState 는 self == nil 분기에서도 counter balance 를 맞추기
        // 위해 강참조로 캡처.
        await state.taskStarted()
        let capturedState = self.state
        Task { [weak self] in
            if let self {
                do {
                    try await self.dispatchFrame(frame)
                } catch {
                    self.logger.error("Frame dispatch failed: \(error)")
                }
            }
            await capturedState.taskFinished()
        }
    }

    private func dispatchFrame(_ frame: SiriusFrame) async throws {
        switch frame.opcode {
        case .fileSystemOpenRequest:
            let req = try FileSystemOpenRequest.fromProtobufBytes(frame.data)
            try await handleOpen(req)
        case .fileSystemCloseRequest:
            let req = try FileSystemCloseRequest.fromProtobufBytes(frame.data)
            try await handleClose(req)
        case .fileSystemReadRequest:
            let req = try FileSystemReadRequest.fromProtobufBytes(frame.data)
            try await handleRead(req)
        case .fileSystemWriteRequest:
            let req = try FileSystemWriteRequest.fromProtobufBytes(frame.data)
            try await handleWrite(req)
        case .fileSystemFlushRequest:
            let req = try FileSystemFlushRequest.fromProtobufBytes(frame.data)
            try await handleFlush(req)
        case .fileSystemStatRequest:
            let req = try FileSystemStatRequest.fromProtobufBytes(frame.data)
            try await handleStat(req)
        case .fileSystemFStatRequest:
            let req = try FileSystemFStatRequest.fromProtobufBytes(frame.data)
            try await handleFStat(req)
        case .fileSystemReadDirRequest:
            let req = try FileSystemReadDirRequest.fromProtobufBytes(frame.data)
            try await handleReadDir(req)
        case .fileSystemMkdirRequest:
            let req = try FileSystemMkdirRequest.fromProtobufBytes(frame.data)
            try await handleMkdir(req)
        case .fileSystemRmdirRequest:
            let req = try FileSystemRmdirRequest.fromProtobufBytes(frame.data)
            try await handleRmdir(req)
        case .fileSystemUnlinkRequest:
            let req = try FileSystemUnlinkRequest.fromProtobufBytes(frame.data)
            try await handleUnlink(req)
        case .fileSystemRenameRequest:
            let req = try FileSystemRenameRequest.fromProtobufBytes(frame.data)
            try await handleRename(req)
        case .fileSystemFTruncateRequest:
            let req = try FileSystemFTruncateRequest.fromProtobufBytes(frame.data)
            try await handleFTruncate(req)
        case .fileSystemRequestStreamReadRequest:
            let req = try FileSystemRequestStreamReadRequest.fromProtobufBytes(frame.data)
            try await handleStreamRead(req)
        case .fileSystemRequestStreamWriteRequest:
            let req = try FileSystemRequestStreamWriteRequest.fromProtobufBytes(frame.data)
            try await handleStreamWrite(req)
        case .fileSystemLockRequest:
            let req = try FileSystemLockRequest.fromProtobufBytes(frame.data)
            try await handleLock(req)
        case .fileSystemUnlockRequest:
            let req = try FileSystemUnlockRequest.fromProtobufBytes(frame.data)
            try await handleUnlock(req)
        case .fileSystemTestLockRequest:
            let req = try FileSystemTestLockRequest.fromProtobufBytes(frame.data)
            try await handleTestLock(req)
        default:
            logger.warning("Received unknown opcode: \(frame.opcode)")
        }
    }

    func handleError(error: any Error) async {
        logger.error("FSAccessMountChannel stream error: \(error)")
        await teardown()
    }

    func handleStreamClose() async {
        let sessionId = self.mountSession.id
        logger.info("FSAccessMountChannel closed (session=\(sessionId)) — releasing handles")
        await teardown()
    }

    private func teardown() async {
        // 진행중인 frame dispatch task 들이 자연 완료될 때까지 대기.
        // 이 시점 이후엔 어떤 task 도 fd 를 사용하지 않음이 보장되므로,
        // 핸들 close 를 안전하게 수행할 수 있다 (use-after-close race 차단).
        await state.waitForDrain()

        // 모든 핸들 close
        let handles = await state.snapshot()
        for h in handles {
            h.closeIfNeeded()
        }
        // 진행 중인 stream coordinator 들 abort
        await abortAllStreamRoutes()

        // RemoteSession 에서 mount session 제거
        if let noctiluca = await noctilucaClient() {
            await MainActor.run {
                noctiluca.fsAccessRemoteSession?.removeFSAccessMountSession(sessionId: mountSession.id)
            }
        }
        mountSession.setMountChannel(nil)
    }

    // MARK: - Open / Close

    private func handleOpen(_ request: FileSystemOpenRequest) async throws {
        // accessMode 검증 (granted access 초과 방지)
        if request.accessMode.rawValue > mountSession.grantedAccess.rawValue {
            try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                code: .permissionDenied,
                message: "Requested accessMode (\(request.accessMode.rawValue)) exceeds granted access (\(mountSession.grantedAccess.rawValue)).")
            return
        }

        // path 정규화
        let resolvedURL: URL
        do {
            resolvedURL = try FSAccessPathValidator.resolve(
                path: request.path,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
        } catch let err as FSAccessPathValidator.ValidationError {
            if case .pathTooLongHard = err {
                await escalateFatalClose(code: .quotaExceeded, reason: err.description)
                return
            }
            try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                code: err.fileSystemErrorCode, message: err.description)
            return
        }

        // handle 한도 검사
        let count = await state.count()
        if count >= FSAccessMountLimits.handlesHard {
            let msg = "Open handle count \(count) exceeds hard threshold \(FSAccessMountLimits.handlesHard) — closing channel."
            logger.error(msg)
            await escalateFatalClose(code: .quotaExceeded, reason: msg)
            return
        }
        if count >= FSAccessMountLimits.handlesWarn {
            logger.warning("Open handle count \(count) exceeds warn threshold \(FSAccessMountLimits.handlesWarn).")
        }
        if count >= FSAccessMountLimits.handlesSpec {
            try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                code: .tooManyHandles, message: "Open handle count \(count) reached spec limit \(FSAccessMountLimits.handlesSpec).")
            return
        }

        let isDirectoryOnly = request.flags.contains(.directoryOnly)
        let isNoFollow = request.flags.contains(.noFollowSymlinks)
        let isAppend = request.flags.contains(.append)

        // directoryOnly → opendir
        if isDirectoryOnly {
            let cstr = resolvedURL.path.withCString { strdup($0) }
            defer { free(cstr) }

            // open(2) with O_DIRECTORY 로 fd 를 잡아 fdopendir 로 stream 생성.
            // `O_NOFOLLOW_ANY` 를 default 로 박아 경로상 어떤 component 의
            // symlink 도 거절 — mount root escape 차단.
            var openFlags: Int32 = O_RDONLY | O_DIRECTORY | kFSAccessOpenExtraFlags
            if isNoFollow { openFlags |= O_NOFOLLOW }
            let fd = noc_open_with_mode(cstr!, openFlags, 0)
            if fd < 0 {
                try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                    code: FSAccessErrorMapper.mapErrno(errno),
                    message: "open(\(resolvedURL.path)) failed for directory.")
                return
            }
            guard let dirStream = Darwin.fdopendir(fd) else {
                let info = FSAccessErrorMapper.errorInfoFromErrno(message: "fdopendir failed")
                _ = Darwin.close(fd)
                try await handle.send(opcode: .fileSystemOpenResponse, message: FileSystemOpenResponse(
                    requestId: request.requestId, success: false, handleId: 0, stat: nil, error: info))
                return
            }

            let statSnapshot = try? makeFStatStruct(fd: fd)
            let fileStat = statSnapshot.map { makeFileStat(from: $0, symlinkTarget: nil) }

            let fsHandle = await state.issueHandle { id in
                FSAccessHandle(id: id, path: resolvedURL, accessMode: request.accessMode,
                    openFlags: request.flags, kind: .directory(dirStream: dirStream))
            }

            try await handle.send(opcode: .fileSystemOpenResponse, message: FileSystemOpenResponse(
                requestId: request.requestId, success: true, handleId: fsHandle.id,
                stat: fileStat, error: nil))
            return
        }

        // 일반 파일 open. directoryOnly 분기와 동일하게 `O_NOFOLLOW_ANY` 를
        // default 로 박아 escape 차단.
        var openFlags: Int32 = kFSAccessOpenExtraFlags
        switch request.accessMode {
        case .read: openFlags |= O_RDONLY
        case .write: openFlags |= O_WRONLY
        case .readWrite: openFlags |= O_RDWR
        default:
            try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                code: .invalidArgument, message: "Unknown accessMode \(request.accessMode.rawValue).")
            return
        }

        switch request.createDisposition {
        case .openExisting:
            break
        case .createNew:
            openFlags |= O_CREAT | O_EXCL
        case .createAlways:
            openFlags |= O_CREAT | O_TRUNC
        case .openOrCreate:
            openFlags |= O_CREAT
        case .truncateExisting:
            openFlags |= O_TRUNC
        default:
            try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                code: .invalidArgument, message: "Unknown createDisposition \(request.createDisposition.rawValue).")
            return
        }

        if isAppend { openFlags |= O_APPEND }
        if isNoFollow { openFlags |= O_NOFOLLOW }

        let mode = mode_t(request.mode == 0 ? 0o644 : request.mode)
        let cstr = resolvedURL.path.withCString { strdup($0) }
        defer { free(cstr) }
        let fd = noc_open_with_mode(cstr!, openFlags, mode)
        if fd < 0 {
            try await sendError(opcode: .fileSystemOpenResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno),
                message: "open(\(resolvedURL.path)) failed.")
            return
        }

        // open 직후 stat snapshot
        let statStruct = try? makeFStatStruct(fd: fd)
        let fileStat = statStruct.map { makeFileStat(from: $0, symlinkTarget: nil) }

        let fsHandle = await state.issueHandle { id in
            FSAccessHandle(id: id, path: resolvedURL, accessMode: request.accessMode,
                openFlags: request.flags, kind: .file(fileDescriptor: fd))
        }

        try await handle.send(opcode: .fileSystemOpenResponse, message: FileSystemOpenResponse(
            requestId: request.requestId, success: true, handleId: fsHandle.id,
            stat: fileStat, error: nil))
    }

    private func handleClose(_ request: FileSystemCloseRequest) async throws {
        guard let h = await state.remove(request.handleId) else {
            try await sendError(opcode: .fileSystemCloseResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) does not exist or was already closed.")
            return
        }

        // implicit fsync (file 핸들에 한해, 쓰기 가능했으면).
        var flushError: ErrorInfo? = nil
        if case .file(let fd) = h.kind, h.accessMode != .read {
            if Darwin.fsync(fd) != 0 {
                flushError = FSAccessErrorMapper.errorInfoFromErrno(message: "fsync during close failed")
            }
        }

        h.closeIfNeeded()

        try await handle.send(opcode: .fileSystemCloseResponse, message: FileSystemCloseResponse(
            requestId: request.requestId,
            success: flushError == nil,
            error: flushError
        ))
    }

    // MARK: - Read / Write / Flush

    private func handleRead(_ request: FileSystemReadRequest) async throws {
        // length hard cap 검사 (per-frame)
        if Int(request.length) > FSAccessMountLimits.inlineBytesHard {
            let msg = "FileSystemReadRequest.length \(request.length) exceeds the 16 MiB per-frame cap."
            logger.error(msg)
            await escalateFatalClose(code: .quotaExceeded, reason: msg)
            return
        }

        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemReadResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }

        if h.accessMode == .write {
            try await sendError(opcode: .fileSystemReadResponse, requestId: request.requestId,
                code: .permissionDenied, message: "Handle was opened with write-only access.")
            return
        }

        let len = min(Int(request.length), FSAccessMountLimits.inlineBytesSpec)
        if len == 0 {
            try await handle.send(opcode: .fileSystemReadResponse, message: FileSystemReadResponse(
                requestId: request.requestId, success: true, data: Data(), isEof: false, error: nil))
            return
        }

        var buffer = Data(count: len)
        let read: Int = buffer.withUnsafeMutableBytes { rawPtr -> Int in
            guard let base = rawPtr.baseAddress else { return -1 }
            return Darwin.pread(fd, base, len, off_t(request.offset))
        }
        if read < 0 {
            try await sendError(opcode: .fileSystemReadResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "pread failed.")
            return
        }

        if read < len {
            buffer = buffer.prefix(read)
        }

        let isEof = read == 0 || (read < len)

        // 압축 method 가 zstd 면 wire bytes 로 압축. 실패하면 per-op ioError 로 응답
        // (spec: 채널 자체는 유지).
        let wireData: Data
        if mountSession.selectedCompressionMethod == .zstd {
            do {
                wireData = try ZstdCodec.compress(buffer)
            } catch {
                logger.error("Read compression failed: \(error)")
                try await sendError(opcode: .fileSystemReadResponse, requestId: request.requestId,
                    code: .ioError, message: "zstd compression failed.")
                return
            }
        } else {
            wireData = buffer
        }

        try await handle.send(opcode: .fileSystemReadResponse, message: FileSystemReadResponse(
            requestId: request.requestId, success: true, data: wireData, isEof: isEof, error: nil))
    }

    private func handleWrite(_ request: FileSystemWriteRequest) async throws {
        if request.data.count > FSAccessMountLimits.inlineBytesHard {
            let msg = "FileSystemWriteRequest.data size \(request.data.count) exceeds the 16 MiB per-frame cap."
            logger.error(msg)
            await escalateFatalClose(code: .quotaExceeded, reason: msg)
            return
        }
        if request.data.count > FSAccessMountLimits.inlineBytesSpec {
            logger.warning("FileSystemWriteRequest.data size \(request.data.count) exceeds spec limit \(FSAccessMountLimits.inlineBytesSpec) — accepting (likely sender bug).")
        }

        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemWriteResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if h.accessMode == .read {
            try await sendError(opcode: .fileSystemWriteResponse, requestId: request.requestId,
                code: .permissionDenied, message: "Handle was opened read-only.")
            return
        }

        // 압축 method 가 zstd 면 wire 로 받은 데이터를 decompress 하고 pwrite. 실패는
        // per-op ioError 로 회복 (spec).
        let payload: Data
        if mountSession.selectedCompressionMethod == .zstd {
            do {
                payload = try ZstdCodec.decompress(request.data)
            } catch {
                logger.error("Write decompression failed: \(error)")
                try await sendError(opcode: .fileSystemWriteResponse, requestId: request.requestId,
                    code: .ioError, message: "zstd decompression failed.")
                return
            }
        } else {
            payload = request.data
        }

        let written: Int = payload.withUnsafeBytes { rawPtr -> Int in
            guard let base = rawPtr.baseAddress else { return -1 }
            // O_APPEND 시 offset 무시 (POSIX 보장)
            return Darwin.pwrite(fd, base, payload.count, off_t(request.offset))
        }
        if written < 0 {
            try await sendError(opcode: .fileSystemWriteResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "pwrite failed.")
            return
        }

        try await handle.send(opcode: .fileSystemWriteResponse, message: FileSystemWriteResponse(
            requestId: request.requestId, success: true, bytesWritten: UInt32(written), error: nil))
    }

    private func handleFlush(_ request: FileSystemFlushRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemFlushResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if h.accessMode == .read {
            // read-only flush 는 no-op success
            try await handle.send(opcode: .fileSystemFlushResponse, message: FileSystemFlushResponse(
                requestId: request.requestId, success: true, error: nil))
            return
        }
        if Darwin.fsync(fd) != 0 {
            try await sendError(opcode: .fileSystemFlushResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "fsync failed.")
            return
        }
        try await handle.send(opcode: .fileSystemFlushResponse, message: FileSystemFlushResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    // MARK: - Stat / FStat

    private func handleStat(_ request: FileSystemStatRequest) async throws {
        let resolvedURL: URL
        do {
            resolvedURL = try FSAccessPathValidator.resolve(
                path: request.path,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
        } catch let err as FSAccessPathValidator.ValidationError {
            if case .pathTooLongHard = err {
                await escalateFatalClose(code: .quotaExceeded, reason: err.description)
                return
            }
            try await sendError(opcode: .fileSystemStatResponse, requestId: request.requestId,
                code: err.fileSystemErrorCode, message: err.description)
            return
        }

        // followSymlinks == true → stat(); false → lstat()
        var statStruct = noc_stat_t()
        let cstr = resolvedURL.path.withCString { strdup($0) }
        defer { free(cstr) }

        let result: Int32
        if request.followSymlinks {
            result = noc_stat(cstr!, &statStruct)
        } else {
            result = noc_lstat(cstr!, &statStruct)
        }
        if result != 0 {
            try await sendError(opcode: .fileSystemStatResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "stat(\(resolvedURL.path)) failed.")
            return
        }

        // followSymlinks 였다면 resolved path 가 mount root 밖으로 escape 했는지 재검사
        if request.followSymlinks {
            if !FSAccessPathValidator.isWithin(resolvedURL, rootResolvedPath: mountSession.resolvedRootPath) {
                try await sendError(opcode: .fileSystemStatResponse, requestId: request.requestId,
                    code: .policyViolation, message: "Symlink target escapes mount root subtree.")
                return
            }
        }

        // symlink 이고 follow 안 했으면 readlink 결과를 채움
        var symlinkTarget: String? = nil
        if !request.followSymlinks && (statStruct.st_mode & S_IFMT) == S_IFLNK {
            symlinkTarget = readlinkString(at: resolvedURL.path)
        }

        let fileStat = makeFileStat(from: statStruct, symlinkTarget: symlinkTarget)
        try await handle.send(opcode: .fileSystemStatResponse, message: FileSystemStatResponse(
            requestId: request.requestId, success: true, stat: fileStat, error: nil))
    }

    private func handleFStat(_ request: FileSystemFStatRequest) async throws {
        guard let h = await state.get(request.handleId) else {
            try await sendError(opcode: .fileSystemFStatResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not open.")
            return
        }
        let fd: Int32
        switch h.kind {
        case .file(let fileDescriptor):
            fd = fileDescriptor
        case .directory(let dir):
            fd = Darwin.dirfd(dir)
        case .none:
            try await sendError(opcode: .fileSystemFStatResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle is closed.")
            return
        }
        guard let statStruct = try? makeFStatStruct(fd: fd) else {
            try await sendError(opcode: .fileSystemFStatResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "fstat failed.")
            return
        }
        let fileStat = makeFileStat(from: statStruct, symlinkTarget: nil)
        try await handle.send(opcode: .fileSystemFStatResponse, message: FileSystemFStatResponse(
            requestId: request.requestId, success: true, stat: fileStat, error: nil))
    }

    // MARK: - ReadDir / Mkdir / Rmdir

    private func handleReadDir(_ request: FileSystemReadDirRequest) async throws {
        guard let h = await state.get(request.handleId), let dirStream = h.dirStream else {
            try await sendError(opcode: .fileSystemReadDirResponse, requestId: request.requestId,
                code: .notDirectory, message: "Handle \(request.handleId) is not an open directory.")
            return
        }

        let maxEntries = min(Int(request.maxEntries == 0 ? UInt32(FSAccessMountLimits.dirEntriesSpec) : request.maxEntries),
                             FSAccessMountLimits.dirEntriesSpec)

        var entries: [DirEntry] = []
        var isEnd = false

        while entries.count < maxEntries {
            errno = 0
            guard let entryPtr = Darwin.readdir(dirStream) else {
                if errno != 0 {
                    try await sendError(opcode: .fileSystemReadDirResponse, requestId: request.requestId,
                        code: FSAccessErrorMapper.mapErrno(errno), message: "readdir failed.")
                    return
                }
                isEnd = true
                break
            }
            let entry = entryPtr.pointee

            // d_name 추출
            let name = withUnsafePointer(to: entry.d_name) { tuplePtr -> String in
                tuplePtr.withMemoryRebound(to: CChar.self, capacity: Int(entry.d_namlen)) {
                    String(cString: $0)
                }
            }
            // . / .. 스킵
            if name == "." || name == ".." { continue }

            // name 길이 체크
            let nameByteCount = name.utf8.count
            if nameByteCount > FSAccessMountLimits.dirNameSpec {
                logger.warning("DirEntry.name byte length \(nameByteCount) exceeds spec limit \(FSAccessMountLimits.dirNameSpec) — keeping entry but flagging.")
            }

            // 각 entry 의 stat 도 같이 채움 (lstat — 디렉토리 안의 심볼릭 링크는 그대로 보존)
            var statStruct = noc_stat_t()
            let entryURL = h.path.appendingPathComponent(name)
            let cstr = entryURL.path.withCString { strdup($0) }
            defer { free(cstr) }
            var fileStat: FileStat?
            if noc_lstat(cstr!, &statStruct) == 0 {
                let symlinkTarget: String? = (statStruct.st_mode & S_IFMT) == S_IFLNK
                    ? readlinkString(at: entryURL.path) : nil
                fileStat = makeFileStat(from: statStruct, symlinkTarget: symlinkTarget)
            }

            entries.append(DirEntry(name: name, stat: fileStat))
        }

        try await handle.send(opcode: .fileSystemReadDirResponse, message: FileSystemReadDirResponse(
            requestId: request.requestId, success: true, entries: entries, isEnd: isEnd, error: nil))
    }

    private func handleMkdir(_ request: FileSystemMkdirRequest) async throws {
        let resolvedURL: URL
        do {
            resolvedURL = try FSAccessPathValidator.resolve(
                path: request.path,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
        } catch let err as FSAccessPathValidator.ValidationError {
            if case .pathTooLongHard = err {
                await escalateFatalClose(code: .quotaExceeded, reason: err.description)
                return
            }
            try await sendError(opcode: .fileSystemMkdirResponse, requestId: request.requestId,
                code: err.fileSystemErrorCode, message: err.description)
            return
        }

        if mountSession.grantedAccess == .read {
            try await sendError(opcode: .fileSystemMkdirResponse, requestId: request.requestId,
                code: .readOnlyFilesystem, message: "Mount session is read-only.")
            return
        }

        let mode = mode_t(request.mode == 0 ? 0o755 : request.mode)
        let cstr = resolvedURL.path.withCString { strdup($0) }
        defer { free(cstr) }
        if Darwin.mkdir(cstr, mode) != 0 {
            try await sendError(opcode: .fileSystemMkdirResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "mkdir failed.")
            return
        }
        try await handle.send(opcode: .fileSystemMkdirResponse, message: FileSystemMkdirResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    private func handleRmdir(_ request: FileSystemRmdirRequest) async throws {
        let resolvedURL: URL
        do {
            resolvedURL = try FSAccessPathValidator.resolve(
                path: request.path,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
        } catch let err as FSAccessPathValidator.ValidationError {
            if case .pathTooLongHard = err {
                await escalateFatalClose(code: .quotaExceeded, reason: err.description)
                return
            }
            try await sendError(opcode: .fileSystemRmdirResponse, requestId: request.requestId,
                code: err.fileSystemErrorCode, message: err.description)
            return
        }

        if mountSession.grantedAccess == .read {
            try await sendError(opcode: .fileSystemRmdirResponse, requestId: request.requestId,
                code: .readOnlyFilesystem, message: "Mount session is read-only.")
            return
        }

        let cstr = resolvedURL.path.withCString { strdup($0) }
        defer { free(cstr) }
        if Darwin.rmdir(cstr) != 0 {
            try await sendError(opcode: .fileSystemRmdirResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "rmdir failed.")
            return
        }
        try await handle.send(opcode: .fileSystemRmdirResponse, message: FileSystemRmdirResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    // MARK: - Unlink / Rename / FTruncate

    private func handleUnlink(_ request: FileSystemUnlinkRequest) async throws {
        let resolvedURL: URL
        do {
            resolvedURL = try FSAccessPathValidator.resolve(
                path: request.path,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
        } catch let err as FSAccessPathValidator.ValidationError {
            if case .pathTooLongHard = err {
                await escalateFatalClose(code: .quotaExceeded, reason: err.description)
                return
            }
            try await sendError(opcode: .fileSystemUnlinkResponse, requestId: request.requestId,
                code: err.fileSystemErrorCode, message: err.description)
            return
        }

        if mountSession.grantedAccess == .read {
            try await sendError(opcode: .fileSystemUnlinkResponse, requestId: request.requestId,
                code: .readOnlyFilesystem, message: "Mount session is read-only.")
            return
        }

        let cstr = resolvedURL.path.withCString { strdup($0) }
        defer { free(cstr) }
        if Darwin.unlink(cstr) != 0 {
            try await sendError(opcode: .fileSystemUnlinkResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "unlink failed.")
            return
        }
        try await handle.send(opcode: .fileSystemUnlinkResponse, message: FileSystemUnlinkResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    private func handleRename(_ request: FileSystemRenameRequest) async throws {
        if mountSession.grantedAccess == .read {
            try await sendError(opcode: .fileSystemRenameResponse, requestId: request.requestId,
                code: .readOnlyFilesystem, message: "Mount session is read-only.")
            return
        }

        let oldURL: URL
        let newURL: URL
        do {
            oldURL = try FSAccessPathValidator.resolve(
                path: request.oldPath,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
            newURL = try FSAccessPathValidator.resolve(
                path: request.newPath,
                mountRoot: mountSession.rootURL,
                resolvedRootPath: mountSession.resolvedRootPath
            )
        } catch let err as FSAccessPathValidator.ValidationError {
            if case .pathTooLongHard = err {
                await escalateFatalClose(code: .quotaExceeded, reason: err.description)
                return
            }
            try await sendError(opcode: .fileSystemRenameResponse, requestId: request.requestId,
                code: err.fileSystemErrorCode, message: err.description)
            return
        }

        let oldC = oldURL.path.withCString { strdup($0) }
        let newC = newURL.path.withCString { strdup($0) }
        defer { free(oldC); free(newC) }
        if Darwin.rename(oldC, newC) != 0 {
            try await sendError(opcode: .fileSystemRenameResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "rename failed.")
            return
        }
        try await handle.send(opcode: .fileSystemRenameResponse, message: FileSystemRenameResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    private func handleFTruncate(_ request: FileSystemFTruncateRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemFTruncateResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if h.accessMode == .read {
            try await sendError(opcode: .fileSystemFTruncateResponse, requestId: request.requestId,
                code: .permissionDenied, message: "Handle was opened read-only.")
            return
        }
        if Darwin.ftruncate(fd, off_t(request.length)) != 0 {
            try await sendError(opcode: .fileSystemFTruncateResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "ftruncate failed.")
            return
        }
        try await handle.send(opcode: .fileSystemFTruncateResponse, message: FileSystemFTruncateResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    // MARK: - Byte-range locking

    private func handleLock(_ request: FileSystemLockRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if request.length == 0 {
            try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                code: .invalidArgument, message: "FileSystemLockRequest.length=0 is invalid (use the 0xFFFFFFFFFFFFFFFF sentinel for whole-file).")
            return
        }
        // accessMode validation per mdproto: shared 는 read 가능, exclusive 는 write 가능 핸들에서만.
        let posixType: Int16
        switch request.type {
        case .shared:
            if h.accessMode == .write {
                try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                    code: .permissionDenied, message: "Shared lock requires read or readWrite access mode.")
                return
            }
            posixType = Int16(F_RDLCK)
        case .exclusive:
            if h.accessMode == .read {
                try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                    code: .permissionDenied, message: "Exclusive lock requires write or readWrite access mode.")
                return
            }
            posixType = Int16(F_WRLCK)
        default:
            try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                code: .invalidArgument, message: "Unknown LockType \(request.type.rawValue).")
            return
        }

        var fl = flock()
        fl.l_type = posixType
        fl.l_whence = Int16(SEEK_SET)
        fl.l_start = off_t(request.offset)
        fl.l_len = request.length == kFSAccessLockLengthSentinel ? 0 : off_t(request.length)
        fl.l_pid = 0

        let result = Darwin.fcntl(fd, F_SETLK, &fl)
        if result != 0 {
            let err = errno
            if err == EAGAIN || err == EACCES {
                try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                    code: .wouldBlock, message: "A conflicting lock already exists on the requested byte range.")
                return
            }
            try await sendError(opcode: .fileSystemLockResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(err), message: "fcntl(F_SETLK) failed.")
            return
        }
        try await handle.send(opcode: .fileSystemLockResponse, message: FileSystemLockResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    private func handleUnlock(_ request: FileSystemUnlockRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemUnlockResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if request.length == 0 {
            try await sendError(opcode: .fileSystemUnlockResponse, requestId: request.requestId,
                code: .invalidArgument, message: "FileSystemUnlockRequest.length=0 is invalid (use the 0xFFFFFFFFFFFFFFFF sentinel for whole-file).")
            return
        }
        _ = h  // silence unused

        var fl = flock()
        fl.l_type = Int16(F_UNLCK)
        fl.l_whence = Int16(SEEK_SET)
        fl.l_start = off_t(request.offset)
        fl.l_len = request.length == kFSAccessLockLengthSentinel ? 0 : off_t(request.length)
        fl.l_pid = 0

        // mdproto: not-held 범위 unlock 도 success 로 보고 (POSIX 와 일치).
        let result = Darwin.fcntl(fd, F_SETLK, &fl)
        if result != 0 {
            try await sendError(opcode: .fileSystemUnlockResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "fcntl(F_UNLCK) failed.")
            return
        }
        try await handle.send(opcode: .fileSystemUnlockResponse, message: FileSystemUnlockResponse(
            requestId: request.requestId, success: true, error: nil))
    }

    private func handleTestLock(_ request: FileSystemTestLockRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemTestLockResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if request.length == 0 {
            try await sendError(opcode: .fileSystemTestLockResponse, requestId: request.requestId,
                code: .invalidArgument, message: "FileSystemTestLockRequest.length=0 is invalid (use the 0xFFFFFFFFFFFFFFFF sentinel for whole-file).")
            return
        }

        let posixType: Int16
        switch request.type {
        case .shared:
            if h.accessMode == .write {
                try await sendError(opcode: .fileSystemTestLockResponse, requestId: request.requestId,
                    code: .permissionDenied, message: "Shared lock requires read or readWrite access mode.")
                return
            }
            posixType = Int16(F_RDLCK)
        case .exclusive:
            if h.accessMode == .read {
                try await sendError(opcode: .fileSystemTestLockResponse, requestId: request.requestId,
                    code: .permissionDenied, message: "Exclusive lock requires write or readWrite access mode.")
                return
            }
            posixType = Int16(F_WRLCK)
        default:
            try await sendError(opcode: .fileSystemTestLockResponse, requestId: request.requestId,
                code: .invalidArgument, message: "Unknown LockType \(request.type.rawValue).")
            return
        }

        var fl = flock()
        fl.l_type = posixType
        fl.l_whence = Int16(SEEK_SET)
        fl.l_start = off_t(request.offset)
        fl.l_len = request.length == kFSAccessLockLengthSentinel ? 0 : off_t(request.length)
        fl.l_pid = 0

        let result = Darwin.fcntl(fd, F_GETLK, &fl)
        if result != 0 {
            try await sendError(opcode: .fileSystemTestLockResponse, requestId: request.requestId,
                code: FSAccessErrorMapper.mapErrno(errno), message: "fcntl(F_GETLK) failed.")
            return
        }

        // F_GETLK: l_type 이 F_UNLCK 면 충돌 없음.
        if fl.l_type == Int16(F_UNLCK) {
            try await handle.send(opcode: .fileSystemTestLockResponse, message: FileSystemTestLockResponse(
                requestId: request.requestId, success: true, canAcquire: true,
                conflictingType: .shared, conflictingOffset: 0, conflictingLength: 0,
                error: nil))
            return
        }

        let conflictingType: LockType = fl.l_type == Int16(F_WRLCK) ? .exclusive : .shared
        // POSIX l_len == 0 → sentinel.
        let conflictingLength: UInt64 = fl.l_len == 0 ? kFSAccessLockLengthSentinel : UInt64(fl.l_len)
        try await handle.send(opcode: .fileSystemTestLockResponse, message: FileSystemTestLockResponse(
            requestId: request.requestId, success: true, canAcquire: false,
            conflictingType: conflictingType,
            conflictingOffset: UInt64(fl.l_start),
            conflictingLength: conflictingLength,
            error: nil))
    }

    // MARK: - Stream Read / Write

    private func handleStreamRead(_ request: FileSystemRequestStreamReadRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemRequestStreamReadResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if h.accessMode == .write {
            try await sendError(opcode: .fileSystemRequestStreamReadResponse, requestId: request.requestId,
                code: .permissionDenied, message: "Handle was opened write-only.")
            return
        }

        let transferId = UUID()
        let route = FSAccessStreamRoute(
            transferId: transferId,
            mountSessionId: mountSession.id,
            kind: .read(handleId: request.handleId, offset: request.offset, length: request.length)
        )
        await registerStreamRoute(route)

        try await handle.send(opcode: .fileSystemRequestStreamReadResponse, message: FileSystemRequestStreamReadResponse(
            requestId: request.requestId, success: true, transferId: transferId, error: nil))

        // 비동기로 outgoing TransferChannel 을 열어 bytes 송신.
        Task { [weak self] in
            guard let self else { return }
            await FSAccessStreamCoordinator.runRead(
                channel: self,
                fd: fd,
                offset: request.offset,
                length: request.length,
                transferId: transferId
            )
            await self.removeStreamRoute(transferId: transferId)
        }
    }

    /// FeatureProvider 가 incoming fsaccess-mount stream-write TransferChannel 을 받았을 때 호출.
    /// 매칭된 route 의 handleId 로 fd 를 찾아 `runWrite` 를 돌린다.
    func handleStreamWriteIncoming(_ transferChannel: TransferChannel, route: FSAccessStreamRoute) async {
        guard case .write(let handleId, let offset, let length) = route.kind else {
            logger.warning("handleStreamWriteIncoming: route.kind is not .write")
            return
        }
        guard let h = await state.get(handleId), let fd = h.fileDescriptor else {
            logger.error("handleStreamWriteIncoming: handle \(handleId) is not an open file (transferId=\(route.transferId))")
            try? await transferChannel.handle.close()
            return
        }
        await FSAccessStreamCoordinator.runWrite(
            transferChannel: transferChannel,
            fd: fd,
            offset: offset,
            length: length,
            transferId: route.transferId
        )
        try? await transferChannel.handle.close()
    }

    private func handleStreamWrite(_ request: FileSystemRequestStreamWriteRequest) async throws {
        guard let h = await state.get(request.handleId), let fd = h.fileDescriptor else {
            try await sendError(opcode: .fileSystemRequestStreamWriteResponse, requestId: request.requestId,
                code: .invalidHandle, message: "Handle \(request.handleId) is not an open file.")
            return
        }
        if h.accessMode == .read {
            try await sendError(opcode: .fileSystemRequestStreamWriteResponse, requestId: request.requestId,
                code: .permissionDenied, message: "Handle was opened read-only.")
            return
        }

        let transferId = UUID()
        let route = FSAccessStreamRoute(
            transferId: transferId,
            mountSessionId: mountSession.id,
            kind: .write(handleId: request.handleId, offset: request.offset, length: request.length)
        )
        await registerStreamRoute(route)

        try await handle.send(opcode: .fileSystemRequestStreamWriteResponse, message: FileSystemRequestStreamWriteResponse(
            requestId: request.requestId, success: true, transferId: transferId, error: nil))

        // incoming TransferChannel 은 FeatureProvider 가 받아서 RemoteSession 의 pending route 와 매칭시킨다.
        // 매칭되면 FSAccessStreamCoordinator.runWrite 가 호출됨.
        // 이 메서드는 여기서 끝.
        _ = fd  // capture to silence unused warning
    }

    // MARK: - RemoteSession glue (stream routes)

    private func registerStreamRoute(_ route: FSAccessStreamRoute) async {
        guard let noctiluca = await noctilucaClient() else { return }
        await MainActor.run {
            noctiluca.fsAccessRemoteSession?.addFSAccessStreamRoute(route)
        }
    }

    private func removeStreamRoute(transferId: UUID) async {
        guard let noctiluca = await noctilucaClient() else { return }
        await MainActor.run {
            noctiluca.fsAccessRemoteSession?.removeFSAccessStreamRoute(transferId: transferId)
        }
    }

    private func abortAllStreamRoutes() async {
        guard let noctiluca = await noctilucaClient() else { return }
        await MainActor.run {
            noctiluca.fsAccessRemoteSession?.abortFSAccessStreamRoutes(forMountSession: mountSession.id)
        }
    }

    private func noctilucaClient() async -> NoctilucaClient? {
        return self.clientSession?.delegate as? NoctilucaClient
    }

    // MARK: - Helpers

    private func sendError(opcode: MessageOpcode, requestId: UInt64, code: FileSystemErrorCode, message: String) async throws {
        let info = FSAccessErrorMapper.errorInfo(code, message: message)

        switch opcode {
        case .fileSystemOpenResponse:
            try await handle.send(opcode: opcode, message: FileSystemOpenResponse(
                requestId: requestId, success: false, handleId: 0, stat: nil, error: info))
        case .fileSystemCloseResponse:
            try await handle.send(opcode: opcode, message: FileSystemCloseResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemReadResponse:
            try await handle.send(opcode: opcode, message: FileSystemReadResponse(
                requestId: requestId, success: false, data: Data(), isEof: false, error: info))
        case .fileSystemWriteResponse:
            try await handle.send(opcode: opcode, message: FileSystemWriteResponse(
                requestId: requestId, success: false, bytesWritten: 0, error: info))
        case .fileSystemFlushResponse:
            try await handle.send(opcode: opcode, message: FileSystemFlushResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemStatResponse:
            try await handle.send(opcode: opcode, message: FileSystemStatResponse(
                requestId: requestId, success: false, stat: nil, error: info))
        case .fileSystemFStatResponse:
            try await handle.send(opcode: opcode, message: FileSystemFStatResponse(
                requestId: requestId, success: false, stat: nil, error: info))
        case .fileSystemReadDirResponse:
            try await handle.send(opcode: opcode, message: FileSystemReadDirResponse(
                requestId: requestId, success: false, entries: [], isEnd: false, error: info))
        case .fileSystemMkdirResponse:
            try await handle.send(opcode: opcode, message: FileSystemMkdirResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemRmdirResponse:
            try await handle.send(opcode: opcode, message: FileSystemRmdirResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemUnlinkResponse:
            try await handle.send(opcode: opcode, message: FileSystemUnlinkResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemRenameResponse:
            try await handle.send(opcode: opcode, message: FileSystemRenameResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemFTruncateResponse:
            try await handle.send(opcode: opcode, message: FileSystemFTruncateResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemRequestStreamReadResponse:
            try await handle.send(opcode: opcode, message: FileSystemRequestStreamReadResponse(
                requestId: requestId, success: false, transferId: UUID(), error: info))
        case .fileSystemRequestStreamWriteResponse:
            try await handle.send(opcode: opcode, message: FileSystemRequestStreamWriteResponse(
                requestId: requestId, success: false, transferId: UUID(), error: info))
        case .fileSystemLockResponse:
            try await handle.send(opcode: opcode, message: FileSystemLockResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemUnlockResponse:
            try await handle.send(opcode: opcode, message: FileSystemUnlockResponse(
                requestId: requestId, success: false, error: info))
        case .fileSystemTestLockResponse:
            try await handle.send(opcode: opcode, message: FileSystemTestLockResponse(
                requestId: requestId, success: false, canAcquire: false,
                conflictingType: .shared, conflictingOffset: 0, conflictingLength: 0,
                error: info))
        default:
            logger.warning("sendError: unhandled response opcode \(opcode) — message: \(message)")
        }
    }

    private func makeFStatStruct(fd: Int32) throws -> noc_stat_t {
        var s = noc_stat_t()
        if noc_fstat(fd, &s) != 0 {
            throw FSAccessHandleError.posixFailure
        }
        return s
    }

    private func makeFileStat(from s: noc_stat_t, symlinkTarget: String?) -> FileStat {
        let type: FileType
        switch s.st_mode & S_IFMT {
        case S_IFREG: type = .file
        case S_IFDIR: type = .directory
        case S_IFLNK: type = .symlink
        case 0: type = .unknown
        default: type = .other
        }

        let mtimeMs = Int64(s.st_mtimespec.tv_sec) * 1000 + Int64(s.st_mtimespec.tv_nsec) / 1_000_000
        let atimeMs = Int64(s.st_atimespec.tv_sec) * 1000 + Int64(s.st_atimespec.tv_nsec) / 1_000_000
        let btimeMs = Int64(s.st_birthtimespec.tv_sec) * 1000 + Int64(s.st_birthtimespec.tv_nsec) / 1_000_000

        return FileStat(
            type: type,
            size: UInt64(s.st_size),
            mode: UInt32(s.st_mode & 0o777),
            mtimeMs: mtimeMs,
            atimeMs: atimeMs,
            btimeMs: btimeMs,
            attributes: FileAttributes(rawValue: 0),
            symlinkTarget: symlinkTarget,
            metadata: [:]
        )
    }

    private func readlinkString(at path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = path.withCString { cstr in
            Darwin.readlink(cstr, &buffer, buffer.count - 1)
        }
        if length < 0 { return nil }
        buffer[Int(length)] = 0
        return String(cString: buffer)
    }

    private func escalateFatalClose(code: FileSystemErrorCode, reason: String) async {
        guard let noctiluca = await noctilucaClient() else {
            logger.warning("escalateFatalClose: NoctilucaClient not reachable — local-only logging")
            try? await handle.close()
            return
        }
        await noctiluca.remoteFault(notice: .protocolViolation, reason: reason)
    }
}

private enum FSAccessHandleError: Error {
    case posixFailure
}
