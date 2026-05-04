//
//  FSAccessChannel.swift
//  NoctilucaServer
//
//  fsaccess control channel — consuming peer (host) 측 구현.
//  See: docs/nocfsaccessd.md, SiriusProtocol/v1/channels/fsaccess.mdproto.md
//

import Foundation

import SiriusKit

import NocFSAccessXPC

// MARK: - Limits (host 발신 측)

private enum FSAccessControlLimits {
    /// `FileSystemListResponse.entries` 수신 시 hard cut-off (mdproto Pattern A).
    static let maxEntriesHard = 1024
    static let maxEntriesWarn = 48
    static let maxEntriesSpec = 32
    /// `FileSystemMountRequest.reason` byte 길이 (host 가 발신할 때 넘기지 않을 self-cap).
    static let reasonSpec = 512
}

// MARK: - Errors

enum FSAccessChannelError: Error {
    case channelClosed
    case responseMismatch
    case timeout
}

// MARK: - FSAccessChannel

/// host 가 *발신* 하는 fsaccess control channel. List / Mount / Unmount 요청을
/// 보내고 응답을 기다린다.
///
/// - Note: ``handle.direction`` 은 항상 ``.local`` 이어야 한다 (NoctilucaFeatureProvider
///   에서 보장). navigator (exposing peer) 가 발신하는 경로는 본 채널이 다루지 않는다.
final class FSAccessChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    let logger = NoctilucaLogger(category: "FSAccessChannel")

    private static let defaultServiceClass: ServiceClass = .background

    let state = FSAccessConsumingState()

    /// requestId → 응답 continuation. 보낼 때 등록, 응답 받으면 resume.
    private let pending = PendingResponses()

    actor PendingResponses {
        private var listConts: [UInt64: CheckedContinuation<FileSystemListResponse, Error>] = [:]
        private var mountConts: [UInt64: CheckedContinuation<FileSystemMountResponse, Error>] = [:]
        private var unmountConts: [UInt64: CheckedContinuation<FileSystemUnmountResponse, Error>] = [:]

        func registerList(id: UInt64, _ cont: CheckedContinuation<FileSystemListResponse, Error>) {
            listConts[id] = cont
        }
        func registerMount(id: UInt64, _ cont: CheckedContinuation<FileSystemMountResponse, Error>) {
            mountConts[id] = cont
        }
        func registerUnmount(id: UInt64, _ cont: CheckedContinuation<FileSystemUnmountResponse, Error>) {
            unmountConts[id] = cont
        }

        func resolveList(_ response: FileSystemListResponse) -> Bool {
            guard let cont = listConts.removeValue(forKey: response.requestId) else { return false }
            cont.resume(returning: response)
            return true
        }
        func resolveMount(_ response: FileSystemMountResponse) -> Bool {
            guard let cont = mountConts.removeValue(forKey: response.requestId) else { return false }
            cont.resume(returning: response)
            return true
        }
        func resolveUnmount(_ response: FileSystemUnmountResponse) -> Bool {
            guard let cont = unmountConts.removeValue(forKey: response.requestId) else { return false }
            cont.resume(returning: response)
            return true
        }

        func failAll(_ error: Error) {
            for (_, cont) in listConts { cont.resume(throwing: error) }
            for (_, cont) in mountConts { cont.resume(throwing: error) }
            for (_, cont) in unmountConts { cont.resume(throwing: error) }
            listConts.removeAll()
            mountConts.removeAll()
            unmountConts.removeAll()
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
        logger.info("FSAccessChannel ready (host = consuming peer).")
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .fileSystemListResponse:
            let response = try FileSystemListResponse.fromProtobufBytes(frame.data)
            if response.entries.count > FSAccessControlLimits.maxEntriesHard {
                let msg = "FileSystemListResponse.entries (\(response.entries.count)) exceeds hard threshold \(FSAccessControlLimits.maxEntriesHard) — closing channel."
                logger.error("\(msg)")
                // ServerNoticeCode 에 .quotaExceeded 가 아직 없으므로 .protocolViolation 으로
                // 보낸다. 본 클래스의 정책은 docs/spec-violation-policy.md \"quotaExceeded\" 코드를
                // 가리키며, ServerNoticeCode 가 구체화되면 함께 갱신할 것.
                await escalateFatalClose(code: .protocolViolation, reason: msg)
                return
            }
            if response.entries.count > FSAccessControlLimits.maxEntriesWarn {
                logger.warning("FileSystemListResponse.entries count \(response.entries.count) exceeds warn threshold \(FSAccessControlLimits.maxEntriesWarn) (spec=\(FSAccessControlLimits.maxEntriesSpec)).")
            }
            if !(await pending.resolveList(response)) {
                logger.warning("Received FileSystemListResponse for unknown requestId=\(response.requestId).")
            }

        case .fileSystemMountResponse:
            let response = try FileSystemMountResponse.fromProtobufBytes(frame.data)
            if !(await pending.resolveMount(response)) {
                logger.warning("Received FileSystemMountResponse for unknown requestId=\(response.requestId).")
            }

        case .fileSystemUnmountResponse:
            let response = try FileSystemUnmountResponse.fromProtobufBytes(frame.data)
            if !(await pending.resolveUnmount(response)) {
                logger.warning("Received FileSystemUnmountResponse for unknown requestId=\(response.requestId).")
            }

        default:
            logger.warning("Received unexpected opcode on host-side fsaccess control channel: \(frame.opcode)")
        }
    }

    func handleError(error: any Error) async {
        logger.error("FSAccessChannel stream error: \(error)")
        await pending.failAll(FSAccessChannelError.channelClosed)
    }

    func handleStreamClose() async {
        logger.info("FSAccessChannel closed.")
        await pending.failAll(FSAccessChannelError.channelClosed)
    }

    // MARK: - Public API (Stage F 가 호출)

    /// `FileSystemListRequest` 를 발신하고 응답을 기다린다.
    func requestList() async throws -> FileSystemListResponse {
        let requestId = await state.issueRequestId()
        let request = FileSystemListRequest(requestId: requestId, flags: 0)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FileSystemListResponse, Error>) in
            Task {
                await pending.registerList(id: requestId, cont)
                do {
                    try await handle.send(opcode: .fileSystemListRequest, message: request)
                } catch {
                    _ = await pending.resolveList(FileSystemListResponse(
                        requestId: requestId,
                        success: false,
                        entries: [],
                        error: ErrorInfo(code: .internal, message: "send failed: \(error)", platformCode: nil, platformName: nil)
                    ))
                }
            }
        }
    }

    /// `FileSystemMountRequest` 를 발신하고 응답을 기다린다.
    func requestMount(entryId: UUID, requestedAccess: AccessMode, reason: String?) async throws -> FileSystemMountResponse {
        let requestId = await state.issueRequestId()

        // Self-cap: 우리는 reason 길이를 spec 한도 안으로 보낸다.
        let safeReason: String?
        if let reason {
            if reason.utf8.count > FSAccessControlLimits.reasonSpec {
                logger.warning("Truncating outgoing FileSystemMountRequest.reason from \(reason.utf8.count) bytes to spec=\(FSAccessControlLimits.reasonSpec).")
                let utf8 = Array(reason.utf8.prefix(FSAccessControlLimits.reasonSpec))
                safeReason = String(decoding: utf8, as: UTF8.self)
            } else {
                safeReason = reason
            }
        } else {
            safeReason = nil
        }

        let request = FileSystemMountRequest(
            requestId: requestId,
            entryId: entryId,
            requestedAccess: requestedAccess,
            reason: safeReason,
            flags: 0
        )

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FileSystemMountResponse, Error>) in
            Task {
                await pending.registerMount(id: requestId, cont)
                do {
                    try await handle.send(opcode: .fileSystemMountRequest, message: request)
                } catch {
                    _ = await pending.resolveMount(FileSystemMountResponse(
                        requestId: requestId,
                        success: false,
                        sessionId: UUID(),
                        grantedAccess: .read,
                        error: ErrorInfo(code: .internal, message: "send failed: \(error)", platformCode: nil, platformName: nil)
                    ))
                }
            }
        }
    }

    /// `FileSystemUnmountRequest` 를 발신하고 응답을 기다린다. 응답이 실패해도
    /// 호출자는 세션을 release 된 것으로 취급해야 한다 (mdproto §IMPLEMENTATION
    /// NOTES — Unmount).
    func requestUnmount(sessionId: UUID) async throws -> FileSystemUnmountResponse {
        let requestId = await state.issueRequestId()
        let request = FileSystemUnmountRequest(requestId: requestId, sessionId: sessionId, flags: 0)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FileSystemUnmountResponse, Error>) in
            Task {
                await pending.registerUnmount(id: requestId, cont)
                do {
                    try await handle.send(opcode: .fileSystemUnmountRequest, message: request)
                } catch {
                    _ = await pending.resolveUnmount(FileSystemUnmountResponse(
                        requestId: requestId,
                        success: false,
                        error: ErrorInfo(code: .internal, message: "send failed: \(error)", platformCode: nil, platformName: nil)
                    ))
                }
            }
        }
    }

    // MARK: - Fatal close

    private func escalateFatalClose(code: ServerNoticeCode, reason: String) async {
        logger.error("Escalating to fatal close: code=\(code.rawValue) reason=\(reason)")
        // Stage F 의 wiring 에서 RemoteSession-equivalent (NoctilucaClientSession) 으로
        // ServerNotice + Goodbye 를 보내는 경로를 연결한다. 현 단계에서는 채널만 닫는다.
        try? await handle.close()
    }
}
