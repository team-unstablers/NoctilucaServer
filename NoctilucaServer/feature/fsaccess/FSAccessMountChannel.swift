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

import NocFSAccessXPC

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
}
