//
//  TransferChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation
import os

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

// MARK: - TransferState

/// TransferChannel의 가변 상태를 보호하는 클래스 (Lock 기반 최적화)
final class TransferState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()

    var startNotification: TransferStartNotification? = nil
    var expectedSequenceNumber: UInt64 = 0
    var receivedTotalBytes: UInt64 = 0
    var dataContinuation: AsyncStream<Data>.Continuation? = nil

    var sendSequenceNumber: UInt64 = 0
    var sendStartTime: ContinuousClock.Instant? = nil
    var sentTotalBytes: UInt64 = 0

    var maxSendBytesPerSecond: Int = 0
    var isCompleted: Bool = false

    func withLock<T>(_ body: (TransferState) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(self)
    }
}

// MARK: - TransferChannel

final class TransferChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    private static let defaultServiceClass: ServiceClass = .background

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

    /// FIXME: prepare()에서만 처음 한번 설정되고 이후 변경되지 않으므로 nonisolated(unsafe) 임시 사용한다.
    nonisolated(unsafe) private(set) var transferDirection: TransferChannelDirection? = nil
    
    /// FIXME: prepare()에서만 처음 한번 설정되고 이후 변경되지 않으므로 nonisolated(unsafe) 임시 사용한다.
    nonisolated(unsafe) private(set) var task: TransferChannelTask? = nil

    private let state = TransferState()

    // AsyncStream 자체는 init 1회 설정 패턴 허용 대상
    nonisolated(unsafe) private(set) var dataStream: AsyncStream<Data>? = nil

    // Post-open 콜백. 한 번 설정된 후 변경되지 않으므로 nonisolated(unsafe) 허용.
    nonisolated(unsafe) var onReady: (@Sendable () -> Void)? = nil

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음.
    nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<TransferChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle

        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
        onReady?()
        onReady = nil
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

        // 속도 제한 설정 캐시
        if shouldSend() {
            let limitKBps = await SettingsStore.shared.settings.transfer.maxUploadSpeedKBps
            state.withLock {
                $0.maxSendBytesPerSecond = limitKBps > 0 ? limitKBps * 1024 : 0
            }
        }

        if shouldRecv() {
            var continuationRef: AsyncStream<Data>.Continuation? = nil
            self.dataStream = AsyncStream<Data> { continuation in
                continuationRef = continuation
            }
            state.withLock {
                $0.dataContinuation = continuationRef
            }
        }
    }

    func shouldRecv() -> Bool {
        return (handle.direction == .local && transferDirection == .download) ||
               (handle.direction == .remote && transferDirection == .upload)
    }

    func shouldSend() -> Bool {
        return (handle.direction == .local && transferDirection == .upload) ||
               (handle.direction == .remote && transferDirection == .download)
    }

    var isCompleted: Bool {
        return state.withLock { $0.isCompleted }
    }

    // MARK: - 수신 (handleFrame)

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        logger.warning("received \(frame.length)")
        
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

        let isDuplicate = state.withLock { state in
            if state.startNotification != nil { return true }
            state.startNotification = notification
            return false
        }

        guard !isDuplicate else {
            logger.error("Received duplicate TransferStartNotification - closing channel")
            state.withLock { $0.dataContinuation?.finish() }
            try? await handle.close()
            return
        }

        logger.info("Transfer started: name=\(notification.name), totalSize=\(notification.totalSize), contentType=\(notification.contentType)")
    }

    private func handleTransferDataChunk(_ frame: SiriusFrame) async throws {
        let chunk = try TransferDataChunk.fromProtobufBytes(frame.data)
        
        logger.info("handleTransferDataChunk() called - frame.length = \(frame.length)")

        let (hasStarted, seqMismatch, expectedSeq) = state.withLock { state -> (Bool, Bool, UInt64) in
            let started = state.startNotification != nil
            let mismatch = chunk.sequenceNumber != state.expectedSequenceNumber
            return (started, mismatch, state.expectedSequenceNumber)
        }

        guard hasStarted else {
            logger.error("Received TransferDataChunk before TransferStartNotification - closing channel")
            state.withLock { $0.dataContinuation?.finish() }
            try? await handle.close()
            return
        }

        guard !seqMismatch else {
            logger.error("Sequence number mismatch: expected \(expectedSeq), got \(chunk.sequenceNumber)")
            state.withLock { $0.dataContinuation?.finish() }
            try? await handle.close()
            return
        }

        // CRC32 무결성 검증
        if chunk.crc32 != 0 {
            let computedCRC = CRC32Util.compute(chunk.data)
            if computedCRC != chunk.crc32 {
                logger.error("CRC32 mismatch at sequence \(chunk.sequenceNumber): expected \(chunk.crc32), computed \(computedCRC)")
                state.withLock { $0.dataContinuation?.finish() }
                try? await handle.close()
                return
            }
        }

        // 데이터를 AsyncStream으로 전달
        let isEof = chunk.isEof
        let dataCount = chunk.data.count

        state.withLock { state in
            state.receivedTotalBytes += UInt64(dataCount)
            state.dataContinuation?.yield(chunk.data)
            state.expectedSequenceNumber += 1
        }

        // EOF 처리
        if isEof {
            handleTransferComplete()
            try? await handle.close()
        }
    }

    private func handleTransferComplete() {
        let (notification, receivedBytes) = state.withLock { state -> (TransferStartNotification?, UInt64) in
            state.dataContinuation?.finish()
            state.isCompleted = true
            return (state.startNotification, state.receivedTotalBytes)
        }

        // totalSize 검증
        if let notification = notification, notification.totalSize > 0 {
            if receivedBytes != notification.totalSize {
                logger.warning("Total size mismatch: expected \(notification.totalSize), received \(receivedBytes)")
            }
        }

        logger.info("Transfer completed: received \(receivedBytes) bytes")
    }

    // MARK: - 송신

    /// 전송 시작 알림을 전송합니다.
    func sendStartNotification(_ notification: TransferStartNotification) async throws {
        guard shouldSend() else {
            logger.error("Cannot send on a receive-only channel")
            return
        }
        try await handle.send(opcode: .transferStartNotification, message: notification)
    }

    /// 단일 청크를 전송합니다. 스트리밍 송신 시 사용.
    func writeChunk(_ chunkData: Data, isEof: Bool) async throws {
        guard shouldSend() else {
            logger.error("Cannot write on a receive-only channel")
            return
        }

        let crc = CRC32Util.compute(chunkData)

        let seqNum = state.withLock { state -> UInt64 in
            let seq = state.sendSequenceNumber
            state.sendSequenceNumber += 1
            if isEof {
                state.isCompleted = true
            }
            return seq
        }

        let chunk = TransferDataChunk(
            sequenceNumber: seqNum,
            data: chunkData,
            crc32: crc,
            isEof: isEof
        )

        try await handle.send(opcode: .transferDataChunk, message: chunk)

        if !isEof {
            try await throttleSendIfNeeded(bytesSent: chunkData.count)
        }
    }

    private func throttleSendIfNeeded(bytesSent: Int) async throws {
        let (maxLimit, startTime, sentBytes) = state.withLock { state -> (Int, ContinuousClock.Instant, UInt64) in
            if state.sendStartTime == nil { state.sendStartTime = ContinuousClock.now }
            state.sentTotalBytes += UInt64(bytesSent)
            return (state.maxSendBytesPerSecond, state.sendStartTime!, state.sentTotalBytes)
        }

        guard maxLimit > 0 else { return }

        let now = ContinuousClock.now
        let expectedDuration = Duration.seconds(Double(sentBytes) / Double(maxLimit))
        let elapsed = now - startTime

        if expectedDuration > elapsed {
            try await Task.sleep(for: expectedDuration - elapsed)
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

        // 보안: 특수 파일(디바이스, 소켓 등) 전송 거부
        let resolvedURL = url.resolvingSymlinksInPath()
        if let fileType = (try? FileManager.default.attributesOfItem(atPath: resolvedURL.path))?[.type] as? FileAttributeType,
           fileType != .typeRegular {
            throw ChannelError.invalidArguments("Refused to transfer special file: \(url.path) (type: \(fileType))")
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

    func handleStreamClose() async {
        let completed = state.withLock { state -> Bool in
            state.dataContinuation?.finish()
            return state.isCompleted
        }
        if !completed {
            logger.warning("Stream closed before transfer completed")
        }
    }

    func handleError(error: any Error) async {
        logger.error("Stream error: \(error)")
        state.withLock { $0.dataContinuation?.finish() }
    }
}

// MARK: - Factory

extension TransferChannel {
    static func createIfAccepts(
        handle: ChannelHandle,
        args: [String]
    ) async throws -> ChannelCreationResult {
        guard let argsSet = TransferChannelArgumentsSet.parse(from: args) else {
            return .rejected(code: -1, reason: "Invalid arguments for transfer channel")
        }

        guard TransferChannel.accepts(argsSet, direction: handle.direction) else {
            return .rejected(code: -1, reason: "Unacceptable arguments for transfer channel")
        }

        let transferChannel = TransferChannel(handle: handle)
        try await transferChannel.prepare(argsSet)

        return .accepted(transferChannel)
    }
}
