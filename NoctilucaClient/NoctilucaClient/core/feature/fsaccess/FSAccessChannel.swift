//
//  FSAccessChannel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//
//  fsaccess control channel — exposing peer 측 구현.
//  See: SiriusProtocol/v1/channels/fsaccess.mdproto.md
//

import Foundation

import SiriusKitClient

// MARK: - Limits

private enum FSAccessControlLimits {
    /// `FileSystemListResponse.entries` 송신 시 자체 cap.
    static let maxEntriesSpec = 32
    /// 한 connection 당 동시에 활성화될 수 있는 mount session 수.
    static let maxConcurrentMountsSpec = 16
    static let maxConcurrentMountsWarn = 24
    static let maxConcurrentMountsHard = 512
    /// `FileSystemMountRequest.reason` byte 길이.
    static let reasonSpec = 512
    static let reasonHard = 8 * 1024
}

// MARK: - FSAccessChannel

final class FSAccessChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    let logger = NoctilucaLogger(category: "FSAccessChannel")

    private static let defaultServiceClass: ServiceClass = .background

    /// 진행 중인 mount session 들. control channel close 시 cascade close 의 출처.
    private let state = State()

    actor State {
        var mountSessions: [UUID: FSAccessMountSession] = [:]
        var registered: Bool = false

        func add(_ session: FSAccessMountSession) {
            mountSessions[session.id] = session
        }

        func remove(_ sessionId: UUID) -> FSAccessMountSession? {
            return mountSessions.removeValue(forKey: sessionId)
        }

        func count() -> Int {
            return mountSessions.count
        }

        func snapshot() -> [FSAccessMountSession] {
            return Array(mountSessions.values)
        }

        func setRegistered(_ value: Bool) {
            registered = value
        }
    }

    nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<FSAccessChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)

        // RemoteSession 단일 인스턴스 등록.
        // 이미 활성 channel 이 있으면 즉시 fatal close.
        let registered = await registerToRemoteSession()
        await state.setRegistered(registered)
        if !registered {
            logger.error("Another fsaccess control channel is already active on this session — closing duplicate.")
            await escalateFatalClose(
                code: .policyViolation,
                reason: "A duplicate fsaccess control channel was opened while another is already active on this connection."
            )
        }
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .fileSystemListRequest:
            let req = try FileSystemListRequest.fromProtobufBytes(frame.data)
            try await handleListRequest(req)

        case .fileSystemMountRequest:
            let req = try FileSystemMountRequest.fromProtobufBytes(frame.data)
            try await handleMountRequest(req)

        case .fileSystemUnmountRequest:
            let req = try FileSystemUnmountRequest.fromProtobufBytes(frame.data)
            try await handleUnmountRequest(req)

        default:
            logger.warning("Received unknown opcode: \(frame.opcode)")
        }
    }

    func handleError(error: any Error) async {
        logger.error("FSAccessChannel stream error: \(error)")
        await cascadeCloseAndDeregister()
    }

    func handleStreamClose() async {
        logger.info("FSAccessChannel closed — cascading close to all mount sessions")
        await cascadeCloseAndDeregister()
    }

    // MARK: - List

    private func handleListRequest(_ request: FileSystemListRequest) async throws {
        let entries = await currentExposedEntries()

        // Self-cap: 우리는 엄격히 spec 한도를 지킨다.
        let capped: [SessionSettings.FSAllowedEntry]
        if entries.count > FSAccessControlLimits.maxEntriesSpec {
            logger.warning("Local fsAllowedEntries (\(entries.count)) exceeds spec limit (\(FSAccessControlLimits.maxEntriesSpec)) — truncating before send.")
            capped = Array(entries.prefix(FSAccessControlLimits.maxEntriesSpec))
        } else {
            capped = entries
        }

        let wireEntries = capped.map { entry in
            FileSystemEntry(
                id: entry.id,
                name: entry.name,
                metadata: ["host-path": entry.path, "acl": entry.acl.rawValue],
                flags: 0
            )
        }

        try await handle.send(opcode: .fileSystemListResponse, message: FileSystemListResponse(
            requestId: request.requestId,
            success: true,
            entries: wireEntries,
            error: nil
        ))
    }

    // MARK: - Mount

    private func handleMountRequest(_ request: FileSystemMountRequest) async throws {
        // reason 길이 hard violation 검사 (Pattern A).
        if let reason = request.reason {
            let byteCount = reason.utf8.count
            if byteCount > FSAccessControlLimits.reasonHard {
                let msg = "FileSystemMountRequest.reason byte length \(byteCount) exceeds hard threshold \(FSAccessControlLimits.reasonHard) — closing channel."
                logger.error(msg)
                await escalateFatalClose(code: .quotaExceeded, reason: msg)
                return
            }
            if byteCount > FSAccessControlLimits.reasonSpec {
                logger.warning("FileSystemMountRequest.reason byte length \(byteCount) exceeds spec limit \(FSAccessControlLimits.reasonSpec) — accepting (likely sender bug).")
            }
        }

        // 동시 mount 수 hard violation 검사.
        let activeCount = await state.count()
        if activeCount >= FSAccessControlLimits.maxConcurrentMountsHard {
            let msg = "Active mount session count \(activeCount) reached hard threshold \(FSAccessControlLimits.maxConcurrentMountsHard) — closing channel."
            logger.error(msg)
            await escalateFatalClose(code: .quotaExceeded, reason: msg)
            return
        }
        if activeCount >= FSAccessControlLimits.maxConcurrentMountsWarn {
            logger.warning("Active mount session count \(activeCount) exceeds warn threshold \(FSAccessControlLimits.maxConcurrentMountsWarn) (spec=\(FSAccessControlLimits.maxConcurrentMountsSpec)).")
        }

        // entry 조회.
        guard let entry = await findExposedEntry(byId: request.entryId) else {
            try await sendMountFailure(requestId: request.requestId, code: .notFound,
                message: "Entry \(request.entryId.uuidString) is not exposed.")
            return
        }

        // 정책 적용.
        let policy = await currentFSAccessPolicy()
        let decision = await resolveConsent(
            policy: policy,
            entry: entry,
            request: request
        )

        switch decision {
        case .deny:
            try await sendMountFailure(requestId: request.requestId, code: .consentDenied,
                message: "User or policy denied the mount request.")
            return

        case .allow(var grantedAccess):
            // 정책 우선: alwaysAllowReadOnly 는 entry ACL 의 read-write 를 read 로 강제한다.
            if policy == .alwaysAllowReadOnly {
                grantedAccess = .read
            } else {
                // entry ACL 이 read-only 인데 read-write 요청이면 read 로 다운그레이드.
                if entry.acl == .readOnly && grantedAccess != .read {
                    grantedAccess = .read
                }
            }

            // grantedAccess 는 requestedAccess 를 초과해선 안 된다 (mdproto 명세).
            if grantedAccess.rawValue > request.requestedAccess.rawValue {
                grantedAccess = request.requestedAccess
            }

            // session 생성.
            let session = FSAccessMountSession(
                id: UUID(),
                entryId: entry.id,
                entryName: entry.name,
                rootURL: URL(fileURLWithPath: entry.path).standardizedFileURL,
                grantedAccess: grantedAccess
            )

            await state.add(session)
            await registerMountSessionWithRemoteSession(session)

            try await handle.send(opcode: .fileSystemMountResponse, message: FileSystemMountResponse(
                requestId: request.requestId,
                success: true,
                sessionId: session.id,
                grantedAccess: grantedAccess,
                error: nil
            ))

            logger.info("Mount granted: session=\(session.id) entry=\(entry.name) access=\(grantedAccess.rawValue)")
        }
    }

    private func sendMountFailure(requestId: UInt64, code: FileSystemErrorCode, message: String) async throws {
        try await handle.send(opcode: .fileSystemMountResponse, message: FileSystemMountResponse(
            requestId: requestId,
            success: false,
            sessionId: UUID(),
            grantedAccess: .read,
            error: FSAccessErrorMapper.errorInfo(code, message: message)
        ))
    }

    // MARK: - Unmount

    private func handleUnmountRequest(_ request: FileSystemUnmountRequest) async throws {
        guard let session = await state.remove(request.sessionId) else {
            try await handle.send(opcode: .fileSystemUnmountResponse, message: FileSystemUnmountResponse(
                requestId: request.requestId,
                success: false,
                error: FSAccessErrorMapper.errorInfo(.invalidSession, message: "Session \(request.sessionId.uuidString) was never issued or was already released.")
            ))
            return
        }

        // 대응하는 mount channel 이 있으면 close (자동으로 mount session 도 정리됨).
        if let mountChannel = session.mountChannel {
            try? await mountChannel.handle.close()
        }

        await deregisterMountSessionFromRemoteSession(session.id)

        try await handle.send(opcode: .fileSystemUnmountResponse, message: FileSystemUnmountResponse(
            requestId: request.requestId,
            success: true,
            error: nil
        ))

        logger.info("Mount released: session=\(session.id)")
    }

    // MARK: - Consent resolution

    private func resolveConsent(
        policy: SessionSettings.FSAccessPolicy,
        entry: SessionSettings.FSAllowedEntry,
        request: FileSystemMountRequest
    ) async -> FSAccessConsentDecision {
        switch policy {
        case .deny:
            return .deny

        case .alwaysAllow:
            return .allow(grantedAccess: request.requestedAccess)

        case .alwaysAllowReadOnly:
            return .allow(grantedAccess: .read)

        case .alwaysAsk:
            // broker 가 없으면 안전하게 deny.
            guard let broker = await currentConsentBroker() else {
                logger.warning("No consent broker available — denying mount request as safe default.")
                return .deny
            }
            let consentRequest = FSAccessConsentRequest(
                entryName: entry.name,
                entryPath: entry.path,
                requestedAccess: request.requestedAccess,
                reason: request.reason
            )
            return await broker.requestConsent(consentRequest)
        }
    }

    // MARK: - RemoteSession glue

    private func currentExposedEntries() async -> [SessionSettings.FSAllowedEntry] {
        guard let noctiluca = await noctilucaClient() else { return [] }
        let settings = await MainActor.run { noctiluca.sessionSettings }
        return settings?.transfer.fsAllowedEntries ?? []
    }

    private func findExposedEntry(byId id: UUID) async -> SessionSettings.FSAllowedEntry? {
        let entries = await currentExposedEntries()
        return entries.first(where: { $0.id == id })
    }

    private func currentFSAccessPolicy() async -> SessionSettings.FSAccessPolicy {
        guard let noctiluca = await noctilucaClient() else { return .deny }
        let settings = await MainActor.run { noctiluca.sessionSettings }
        return settings?.transfer.fsAccessPolicy ?? .alwaysAsk
    }

    private func currentConsentBroker() async -> (any FSAccessConsentBroker)? {
        guard let noctiluca = await noctilucaClient() else { return nil }
        return await MainActor.run { noctiluca.fsAccessConsentBroker }
    }

    @MainActor
    private func registerToRemoteSession() async -> Bool {
        guard let noctiluca = await noctilucaClient() else { return true }
        guard let session = noctiluca.fsAccessRemoteSession else { return true }
        return session.registerFSAccessChannel(self)
    }

    @MainActor
    private func registerMountSessionWithRemoteSession(_ session: FSAccessMountSession) async {
        guard let noctiluca = await noctilucaClient() else { return }
        noctiluca.fsAccessRemoteSession?.addFSAccessMountSession(session)
    }

    @MainActor
    private func deregisterMountSessionFromRemoteSession(_ sessionId: UUID) async {
        guard let noctiluca = await noctilucaClient() else { return }
        noctiluca.fsAccessRemoteSession?.removeFSAccessMountSession(sessionId: sessionId)
    }

    private func noctilucaClient() async -> NoctilucaClient? {
        return self.clientSession?.delegate as? NoctilucaClient
    }

    // MARK: - Cascade close + escalation

    private func cascadeCloseAndDeregister() async {
        let sessions = await state.snapshot()
        for session in sessions {
            if let mountChannel = session.mountChannel {
                try? await mountChannel.handle.close()
            }
            await deregisterMountSessionFromRemoteSession(session.id)
        }
        await state.setRegistered(false)

        if let noctiluca = await noctilucaClient() {
            await MainActor.run {
                noctiluca.fsAccessRemoteSession?.unregisterFSAccessChannel(self)
            }
        }
    }

    private func escalateFatalClose(code: FileSystemErrorCode, reason: String) async {
        guard let noctiluca = await noctilucaClient() else {
            logger.warning("escalateFatalClose: NoctilucaClient not reachable — local-only logging")
            try? await handle.close()
            return
        }
        // FileSystemErrorCode 와 ServerNoticeCode 를 매핑.
        let noticeCode: ServerNoticeCode
        switch code {
        case .quotaExceeded:
            noticeCode = .protocolViolation
        case .policyViolation:
            noticeCode = .protocolViolation
        default:
            noticeCode = .protocolViolation
        }
        await noctiluca.remoteFault(notice: noticeCode, reason: reason)
    }
}
