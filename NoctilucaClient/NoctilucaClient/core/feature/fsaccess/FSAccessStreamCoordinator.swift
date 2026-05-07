//
//  FSAccessStreamCoordinator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//
//  Stream Read/Write 의 outgoing/incoming TransferChannel 핸드오프 담당.
//

import Foundation
import Darwin

import SiriusKitClient

/// fsaccess_mount 의 가상 path 컨벤션.
///   args[0] = "fsaccess-mount"
///   args[1] = transferId UUID string
enum FSAccessStreamArgs {
    static let purposeRaw = "fsaccess-mount"

    static func make(transferId: UUID) -> [String] {
        return [purposeRaw, transferId.uuidString]
    }

    static func parseTransferId(args: [String]) -> UUID? {
        guard args.count >= 2 else { return nil }
        guard args[0] == purposeRaw else { return nil }
        return UUID(uuidString: args[1])
    }
}

/// 한 번의 stream 전송 동안의 로직을 모은 namespace.
enum FSAccessStreamCoordinator {
    private static let logger = NoctilucaLogger(category: "FSAccessStreamCoordinator")

    /// `0xFFFF_FFFF_FFFF_FFFF` = "stream until EOF" sentinel.
    private static let unboundedLength: UInt64 = .max

    /// Read 스트림: 클라가 sender. local TransferChannel 을 직접 열어 bytes 를 push 한다.
    ///
    /// - Parameters:
    ///   - channel: source mount channel (clientSession 추출용)
    ///   - fd: source file descriptor
    ///   - offset: 시작 offset
    ///   - length: 송신할 바이트 수. `.max` 면 EOF 까지.
    ///   - transferId: 클라이언트가 발급한 transferId (서버는 이 값으로 매칭)
    static func runRead(
        channel: FSAccessMountChannel,
        fd: Int32,
        offset: UInt64,
        length: UInt64,
        transferId: UUID
    ) async {
        guard let session = channel.clientSession else {
            logger.error("runRead: clientSession unreachable for transferId=\(transferId)")
            return
        }

        let args = FSAccessStreamArgs.make(transferId: transferId)

        let transferChannel: TransferChannel
        do {
            guard let opened = try await session.channelManager.openChannel(
                for: .transfer,
                identifier: ChannelIdentifier(),
                args: args
            ) as? TransferChannel else {
                logger.error("runRead: opened channel is not TransferChannel (transferId=\(transferId))")
                return
            }
            transferChannel = opened
        } catch {
            logger.error("runRead: failed to open TransferChannel: \(error)")
            return
        }

        defer {
            Task { try? await transferChannel.handle.close() }
        }

        // 총 송신할 byte 수. unbounded 면 EOF 까지.
        let totalSize: UInt64 = length == unboundedLength ? 0 : length

        do {
            try await transferChannel.sendStartNotification(TransferStartNotification(
                name: "fsaccess_mount/\(transferId.uuidString)",
                totalSize: totalSize,
                contentType: "application/octet-stream",
                description: "fsaccess_mount stream read (transferId=\(transferId))"
            ))
        } catch {
            logger.error("runRead: sendStartNotification failed: \(error)")
            return
        }

        let chunkSize = 64 * 1024
        var currentOffset = off_t(offset)
        var remaining: Int64 = length == unboundedLength ? .max : Int64(length)

        while remaining > 0 {
            let toRead = remaining == .max ? chunkSize : min(chunkSize, Int(remaining))

            var buffer = Data(count: toRead)
            let read: Int = buffer.withUnsafeMutableBytes { rawPtr -> Int in
                guard let base = rawPtr.baseAddress else { return -1 }
                return Darwin.pread(fd, base, toRead, currentOffset)
            }
            if read < 0 {
                logger.error("runRead: pread failed at offset \(currentOffset) (errno=\(errno))")
                break
            }
            if read == 0 {
                break  // EOF
            }
            if read < toRead {
                buffer = buffer.prefix(read)
            }

            do {
                try await transferChannel.write(buffer)
            } catch {
                logger.error("runRead: TransferChannel.write failed: \(error)")
                break
            }

            currentOffset += off_t(read)
            if remaining != .max {
                remaining -= Int64(read)
            }
        }

        logger.info("runRead: completed transferId=\(transferId) totalOffsetReached=\(currentOffset)")
    }

    /// Write 스트림: 클라가 receiver. 서버가 open 한 incoming TransferChannel 의 bytes 를
    /// pwrite 으로 disk 에 기록한다.
    ///
    /// 이 함수는 `NoctilucaFeatureProvider` 가 incoming TransferChannel 을 받았을 때
    /// pending route 와 매칭하여 호출한다.
    static func runWrite(
        transferChannel: TransferChannel,
        fd: Int32,
        offset: UInt64,
        length: UInt64,
        transferId: UUID
    ) async {
        guard let dataStream = transferChannel.dataStream else {
            logger.error("runWrite: incoming TransferChannel has no dataStream (transferId=\(transferId))")
            return
        }

        let limit: Int64 = length == unboundedLength ? .max : Int64(length)
        var written: Int64 = 0
        var currentOffset = off_t(offset)

        for await chunk in dataStream {
            if chunk.isEmpty { continue }

            let chunkSize = chunk.count
            if limit != .max && written + Int64(chunkSize) > limit {
                logger.error("runWrite: incoming bytes exceeded declared length (limit=\(limit), already=\(written), chunk=\(chunkSize)) — aborting")
                break
            }

            let writeResult: Int = chunk.withUnsafeBytes { rawPtr -> Int in
                guard let base = rawPtr.baseAddress else { return -1 }
                return Darwin.pwrite(fd, base, chunkSize, currentOffset)
            }
            if writeResult < 0 {
                logger.error("runWrite: pwrite failed at offset \(currentOffset) (errno=\(errno))")
                break
            }
            if writeResult < chunkSize {
                logger.warning("runWrite: partial pwrite (\(writeResult)/\(chunkSize)) at offset \(currentOffset) — continuing")
            }
            currentOffset += off_t(writeResult)
            written += Int64(writeResult)

            if limit != .max && written >= limit {
                break
            }
        }

        if let transferError = transferChannel.transferError {
            logger.warning("runWrite: TransferChannel completed with error: \(transferError)")
        }

        logger.info("runWrite: completed transferId=\(transferId) writtenBytes=\(written)")
    }
}
