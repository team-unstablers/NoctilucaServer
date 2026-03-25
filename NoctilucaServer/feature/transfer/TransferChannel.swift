//
//  TransferChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation

import SiriusKit
import zlib

// MARK: - CRC32 Utility

private enum CRC32Util {
    static func compute(_ data: Data) -> UInt32 {
        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return UInt32(zlib.crc32(0, nil, 0))
            }
            return UInt32(zlib.crc32(0, baseAddress.assumingMemoryBound(to: UInt8.self), uInt(data.count)))
        }
    }
}

// MARK: - Transfer Channel Types

struct TransferChannelPurpose: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let fileTransfer = Self(rawValue: "file-transfer")
    public static let clipboardData = Self(rawValue: "clipboard-data")
}

struct TransferChannelDirection: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let upload = Self(rawValue: "upload")
    public static let download = Self(rawValue: "download")
}

struct TransferChannelArgumentsSet {
    /// 전송 목적
    let purpose: TransferChannelPurpose
    /// 전송 방향
    let direction: TransferChannelDirection

    /// 전송과 관련된 추가적인 인자들. 예를 들어, 파일 전송의 경우 파일 이름, 크기 등이 포함될 수 있음.
    let args: [String]
}

enum TransferChannelTask {
    case fileTransfer(name: String, path: URL?, offset: Int64, length: Int64)
    case clipboardData(itemIndex: Int, representationIndex: Int)
}

extension TransferChannelArgumentsSet {
    static func parse(from args: [String]) -> TransferChannelArgumentsSet? {
        guard args.count >= 2 else {
            return nil
        }

        let purpose = TransferChannelPurpose(rawValue: args[0])
        let direction = TransferChannelDirection(rawValue: args[1])

        let additionalArgs = Array(args.dropFirst(2))

        return TransferChannelArgumentsSet(purpose: purpose, direction: direction, args: additionalArgs)
    }

    func serialize() -> [String] {
        return [purpose.rawValue, direction.rawValue] + args
    }
}

// MARK: - TransferChannel

class TransferChannel: Channel {
    override var serviceClass: ServiceClass { .background }

    static let defaultChunkSize: Int = 64 * 1024

    /// 주어진 argument set가 이 채널 구현체에서 처리 가능한지 판단합니다.
    static func accepts(_ argsSet: TransferChannelArgumentsSet, direction: ChannelDirection) -> Bool {
        let acceptedPurpose: Set<TransferChannelPurpose> = [.fileTransfer, .clipboardData]
        let acceptedDirection: Set<TransferChannelDirection> = [.upload, .download]

        return (
            acceptedPurpose.contains(argsSet.purpose) &&
            acceptedDirection.contains(argsSet.direction)
        )
    }


    let logger = NoctilucaLogger(category: "TransferChannel")

    private(set) var transferDirection: TransferChannelDirection? = nil
    private(set) var task: TransferChannelTask? = nil

    // MARK: 수신 상태
    private var startNotification: TransferStartNotification? = nil
    private var expectedSequenceNumber: UInt64 = 0
    private var receivedTotalBytes: UInt64 = 0
    private var dataContinuation: AsyncStream<Data>.Continuation? = nil
    private(set) var dataStream: AsyncStream<Data>? = nil

    // MARK: 송신 상태
    private var sendSequenceNumber: UInt64 = 0

    private(set) var isCompleted: Bool = false

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    func prepare(_ argsSet: TransferChannelArgumentsSet) async throws {
        self.transferDirection = argsSet.direction

        switch argsSet.purpose {
        case .fileTransfer:
            guard argsSet.args.count >= 4,
                  let offset = Int64(argsSet.args[2]),
                  let length = Int64(argsSet.args[3])
            else {
                throw ChannelError.invalidArguments("Invalid arguments for file transfer")
            }

            let fileName = argsSet.args[0]
            let filePathString = argsSet.args[1]
            let filePath = URL(fileURLWithPath: filePathString)

            self.task = .fileTransfer(name: fileName, path: filePath, offset: offset, length: length)

        case .clipboardData:
            guard argsSet.args.count >= 2,
                  let itemIndex = Int(argsSet.args[0]),
                  let representationIndex = Int(argsSet.args[1])
            else {
                throw ChannelError.invalidArguments("Invalid arguments for clipboard data transfer")
            }

            self.task = .clipboardData(itemIndex: itemIndex, representationIndex: representationIndex)
        default:
            break
        }

        if shouldRecv() {
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            self.dataStream = stream
            self.dataContinuation = continuation
        }
    }

    func shouldRecv() -> Bool {
        return (direction == .local && transferDirection == .download) ||
               (direction == .remote && transferDirection == .upload)
    }

    func shouldSend() -> Bool {
        return (direction == .local && transferDirection == .upload) ||
               (direction == .remote && transferDirection == .download)
    }

    // MARK: - 수신 (handleFrame)

    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        guard shouldRecv() else {
            logger.warning("Received frame on a channel that should not receive data - ignoring")
            return
        }

        switch frame.opcode {
        case .transferStartNotification:
            try await handleTransferStartNotification(frame)

        case .transferDataChunk:
            try await handleTransferDataChunk(frame)

        default:
            logger.warning("Received unexpected opcode: \(frame.opcode) - ignoring")
        }
    }

    private func handleTransferStartNotification(_ frame: SiriusFrame) async throws {
        let notification = try TransferStartNotification.fromProtobufBytes(frame.data)

        guard startNotification == nil else {
            logger.error("Received duplicate TransferStartNotification - closing channel")
            dataContinuation?.finish()
            Task { [weak self] in try await self?.close() }
            return
        }

        self.startNotification = notification
        logger.info("Transfer started: name=\(notification.name), totalSize=\(notification.totalSize), contentType=\(notification.contentType)")
    }

    private func handleTransferDataChunk(_ frame: SiriusFrame) async throws {
        guard startNotification != nil else {
            logger.error("Received TransferDataChunk before TransferStartNotification - closing channel")
            dataContinuation?.finish()
            Task { [weak self] in try await self?.close() }
            return
        }

        let chunk = try TransferDataChunk.fromProtobufBytes(frame.data)

        // 시퀀스 번호 검증
        guard chunk.sequenceNumber == expectedSequenceNumber else {
            logger.error("Sequence number mismatch: expected \(self.expectedSequenceNumber), got \(chunk.sequenceNumber)")
            dataContinuation?.finish()
            Task { [weak self] in try await self?.close() }
            return
        }

        // CRC32 무결성 검증
        if chunk.crc32 != 0 {
            let computedCRC = CRC32Util.compute(chunk.data)
            if computedCRC != chunk.crc32 {
                logger.error("CRC32 mismatch at sequence \(chunk.sequenceNumber): expected \(chunk.crc32), computed \(computedCRC)")
                dataContinuation?.finish()
                Task { [weak self] in try await self?.close() }
                return
            }
        }

        // 데이터를 AsyncStream으로 전달
        receivedTotalBytes += UInt64(chunk.data.count)
        dataContinuation?.yield(chunk.data)
        expectedSequenceNumber += 1

        // EOF 처리
        // close()는 streamEventLoopTask.result를 await하므로,
        // streamEventLoop 내부에서 직접 호출하면 self-deadlock이 발생한다.
        if chunk.isEof {
            handleTransferComplete()
            Task { [weak self] in try await self?.close() }
        }
    }

    private func handleTransferComplete() {
        // totalSize 검증
        if let notification = startNotification, notification.totalSize > 0 {
            if receivedTotalBytes != notification.totalSize {
                logger.warning("Total size mismatch: expected \(notification.totalSize), received \(self.receivedTotalBytes)")
            }
        }

        dataContinuation?.finish()
        isCompleted = true
        logger.info("Transfer completed: received \(self.receivedTotalBytes) bytes")
    }

    // MARK: - 송신

    /// 전송 시작 알림을 전송합니다.
    func sendStartNotification(_ notification: TransferStartNotification) async throws {
        guard shouldSend() else {
            logger.error("Cannot send on a receive-only channel")
            return
        }
        try await send(opcode: .transferStartNotification, message: notification)
    }

    /// 단일 청크를 전송합니다. 스트리밍 송신 시 사용.
    func writeChunk(_ chunkData: Data, isEof: Bool) async throws {
        guard shouldSend() else {
            logger.error("Cannot write on a receive-only channel")
            return
        }

        let crc = CRC32Util.compute(chunkData)

        let chunk = TransferDataChunk(
            sequenceNumber: sendSequenceNumber,
            data: chunkData,
            crc32: crc,
            isEof: isEof
        )

        try await send(opcode: .transferDataChunk, message: chunk)
        sendSequenceNumber += 1

        if isEof {
            isCompleted = true
        }
    }

    /// 전체 데이터를 청크로 분할하여 전송합니다.
    func write(_ data: Data) async throws {
        guard shouldSend() else {
            logger.error("Cannot write on a receive-only channel")
            return
        }

        let chunkSize = Self.defaultChunkSize
        var offset = 0

        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunkData = data.subdata(in: offset..<end)
            let isEof = (end >= data.count)

            try await writeChunk(chunkData, isEof: isEof)
            offset = end
        }

        // 빈 데이터의 경우 즉시 EOF 전송
        if data.isEmpty {
            try await writeChunk(Data(), isEof: true)
        }
    }

    /// 디스크의 파일을 청크 단위로 읽어 전송합니다.
    func writeFromFile(at url: URL, offset: Int64 = 0, length: Int64 = -1) async throws {
        guard shouldSend() else {
            logger.error("Cannot write on a receive-only channel")
            return
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        if offset > 0 {
            try fileHandle.seek(toOffset: UInt64(offset))
        }

        let chunkSize = Self.defaultChunkSize
        var remaining = length < 0 ? Int64.max : length

        while remaining > 0 {
            let readSize = min(Int(remaining), chunkSize)
            guard let chunkData = try fileHandle.read(upToCount: readSize),
                  !chunkData.isEmpty else {
                // EOF
                try await writeChunk(Data(), isEof: true)
                return
            }

            remaining -= Int64(chunkData.count)
            let isEof = (remaining <= 0) || chunkData.count < readSize
            try await writeChunk(chunkData, isEof: isEof)

            if isEof { return }
        }
    }

    // MARK: - 스트림 종료 처리

    override func handleStreamClose() {
        if !isCompleted {
            logger.warning("Stream closed before transfer completed")
        }
        dataContinuation?.finish()
        super.handleStreamClose()
    }

    override func handleStreamError(error: any Error) {
        logger.error("Stream error: \(error)")
        dataContinuation?.finish()
        super.handleStreamError(error: error)
    }
}

// MARK: - Factory

extension TransferChannel {
    static func createIfAccepts(
        _ streamHolder: StreamHolder,
        identifier: ChannelIdentifier,
        direction: ChannelDirection,
        args: [String]
    ) async throws -> ChannelCreationResult {
        guard let argsSet = TransferChannelArgumentsSet.parse(from: args) else {
            return .rejected(code: -1, reason: "Invalid arguments for transfer channel")
        }

        guard TransferChannel.accepts(argsSet, direction: direction) else {
            return .rejected(code: -1, reason: "Unacceptable arguments for transfer channel")
        }

        let transferChannel = TransferChannel(using: streamHolder, identifier: identifier, direction: direction)
        try await transferChannel.prepare(argsSet)

        return .accepted(transferChannel)
    }
}
