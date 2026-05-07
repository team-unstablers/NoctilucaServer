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

// MARK: - Task

enum TransferChannelTask {
    case fileTransfer(name: String, path: URL?, offset: Int64, length: Int64)
    case clipboardData(itemIndex: Int, representationIndex: Int)
}

// MARK: - TransferChannelError

enum TransferChannelError: Error, CustomStringConvertible {
    /// 수신된 누적 바이트가 TransferStartNotification.totalSize를 초과함
    case totalSizeExceeded(expected: UInt64, received: UInt64)
    /// EOF 시점에 수신된 누적 바이트가 totalSize와 일치하지 않음
    case totalSizeMismatch(expected: UInt64, received: UInt64)
    /// `TransferReady` 가 timeout 안에 도착하지 않음
    case transferReadyTimeout
    /// `TransferReady` 가 candidate list 에 없는 method 를 골랐음
    case transferReadyNegotiationFailed(method: String)

    var description: String {
        switch self {
        case .totalSizeExceeded(let expected, let received):
            return "Received bytes (\(received)) exceeded declared totalSize (\(expected))"
        case .totalSizeMismatch(let expected, let received):
            return "Received bytes (\(received)) do not match declared totalSize (\(expected)) at EOF"
        case .transferReadyTimeout:
            return "TransferReady did not arrive within the negotiated timeout"
        case .transferReadyNegotiationFailed(let method):
            return "TransferReady picked compression method '\(method)' that was not advertised"
        }
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
    /// 수신 중 발생한 치명적 오류. 스트림 소비자가 완료 후 확인하여 결과를 폐기해야 한다.
    var transferError: TransferChannelError? = nil

    /// 압축 협상 결과. `TransferReady` 수신/송신 후 단 한 번 set 된다.
    var negotiatedCompression: CompressionMethod = .none
    /// `TransferReady` 가 channel 당 1회 처리됐는지 (sender / receiver 양쪽 모두 추적).
    var transferReadySettled: Bool = false
    /// sender 측에서 `TransferReady` 도착을 기다리는 continuation.
    var transferReadyAwaiter: CheckedContinuation<Void, Error>? = nil

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
        let acceptedPurpose: Set<TransferChannelPurpose> = [.fileTransfer, .clipboardData, .fsaccessMount]
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

    /// channel-opener (sender 또는 receiver) 가 광고한 compression candidate 목록.
    nonisolated(unsafe) private(set) var proposedCompressionMethods: [CompressionMethod] = []

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

        // receiver 측이라면 ChannelStartResponse 직후 즉시 TransferReady 발신.
        if shouldRecv() {
            do {
                try await emitTransferReadyIfNeeded()
            } catch {
                logger.error("Failed to emit TransferReady: \(error)")
                try? await handle.close()
                return
            }
        }

        onReady?()
        onReady = nil
    }

    func prepare(_ argsSet: TransferChannelArgumentsSet) async throws {
        self.transferDirection = argsSet.direction
        self.proposedCompressionMethods = argsSet.proposedCompressionMethods

        switch argsSet.purpose {
        case .fileTransfer:
            let purposeArgs = argsSet.purposeArgs
            guard let name = purposeArgs["name"],
                  let lengthRaw = purposeArgs["length"],
                  let lengthU64 = UInt64(lengthRaw)
            else {
                throw ChannelError.invalidArguments("Invalid arguments for file transfer")
            }
            let offsetU64 = UInt64(purposeArgs["offset"] ?? "0") ?? 0

            let pathString = purposeArgs["path"]
            let filePath: URL? = pathString.flatMap { URL(fileURLWithPath: $0) }

            // length 가 UINT64_MAX (= "until EOF") 면 length<0 으로 fallthrough.
            let length: Int64 = lengthU64 == UInt64.max ? -1 : Int64(clamping: lengthU64)
            let offset = Int64(clamping: offsetU64)

            self.task = .fileTransfer(name: name, path: filePath, offset: offset, length: length)

        case .clipboardData:
            let purposeArgs = argsSet.purposeArgs
            guard let itemIndexRaw = purposeArgs["item-index"],
                  let itemIndex = Int(itemIndexRaw),
                  let reprIndexRaw = purposeArgs["representation-index"],
                  let reprIndex = Int(reprIndexRaw)
            else {
                throw ChannelError.invalidArguments("Invalid arguments for clipboard data transfer")
            }

            self.task = .clipboardData(itemIndex: itemIndex, representationIndex: reprIndex)
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

    /// 수신 중 감지된 치명적 오류. dataStream 소비가 끝난 뒤 소비자가 확인해야 한다.
    /// non-nil이면 수신된 데이터는 불완전/오염 상태이므로 결과 파일/버퍼를 폐기해야 한다.
    var transferError: TransferChannelError? {
        return state.withLock { $0.transferError }
    }

    /// 협상된 compression method (TransferReady 처리 후 안정).
    var negotiatedCompression: CompressionMethod {
        return state.withLock { $0.negotiatedCompression }
    }

    // MARK: - 수신 (handleFrame)

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .transferReady:
            try await handleTransferReady(frame)

        case .transferStartNotification:
            guard shouldRecv() else {
                logger.warning("Received TransferStartNotification on a send channel - ignoring")
                return
            }
            try await handleTransferStartNotification(frame)

        case .transferDataChunk:
            guard shouldRecv() else {
                logger.warning("Received TransferDataChunk on a send channel - ignoring")
                return
            }
            try await handleTransferDataChunk(frame)

        default:
            logger.warning("Received unexpected opcode: \(frame.opcode) - ignoring")
        }
    }

    private func handleTransferReady(_ frame: SiriusFrame) async throws {
        let ready = try TransferReady.fromProtobufBytes(frame.data)

        // sender 측만 TransferReady 를 처리해야 함. receiver 가 자기 자신이 보낸 메시지를
        // loopback 형태로 받지는 않지만, malicious peer 대비.
        guard shouldSend() else {
            logger.error("Received TransferReady on a receive-only channel - closing")
            try? await handle.close()
            return
        }

        let alreadySettled = state.withLock { state -> Bool in
            if state.transferReadySettled { return true }
            state.transferReadySettled = true
            return false
        }
        guard !alreadySettled else {
            logger.error("Received duplicate TransferReady - closing channel")
            try? await handle.close()
            return
        }

        let raw = ready.compressionMethod.rawValue
        let method: CompressionMethod = raw.isEmpty ? .none : ready.compressionMethod

        // candidate 검증: method == none 은 항상 OK. 그 외에는 광고된 candidate 안에 있어야 함.
        if method != .none && !proposedCompressionMethods.contains(method) {
            let awaiter = state.withLock { state -> CheckedContinuation<Void, Error>? in
                let cont = state.transferReadyAwaiter
                state.transferReadyAwaiter = nil
                return cont
            }
            awaiter?.resume(throwing: TransferChannelError.transferReadyNegotiationFailed(method: raw))
            logger.error("TransferReady negotiation failed: peer picked '\(raw)', not in advertised candidates")
            try? await handle.close()
            return
        }

        let awaiter = state.withLock { state -> CheckedContinuation<Void, Error>? in
            state.negotiatedCompression = method
            let cont = state.transferReadyAwaiter
            state.transferReadyAwaiter = nil
            return cont
        }
        logger.info("TransferReady accepted: compressionMethod=\(method.rawValue)")
        awaiter?.resume()
    }

    /// receiver 측에서 channel-ready 직후 1회 emit.
    private func emitTransferReadyIfNeeded() async throws {
        let alreadySent = state.withLock { state -> Bool in
            if state.transferReadySettled { return true }
            state.transferReadySettled = true
            return false
        }
        guard !alreadySent else { return }

        // 결정 정책: candidate list 의 첫 번째로 인식 가능한 method (현 시점 zstd only).
        // 인식 불가하거나 candidate 가 없으면 none.
        var chosen: CompressionMethod = .none
        for candidate in proposedCompressionMethods {
            if candidate == .zstd {
                chosen = .zstd
                break
            }
        }
        state.withLock { $0.negotiatedCompression = chosen }
        logger.info("TransferReady picked: compressionMethod=\(chosen.rawValue)")
        try await handle.send(opcode: .transferReady, message: TransferReady(compressionMethod: chosen))
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

        // CRC32 무결성 검증 (optional 필드, 부재 시 skip).
        if let expectedCRC = chunk.crc32 {
            let computedCRC = CRC32Util.compute(chunk.data)
            if computedCRC != expectedCRC {
                logger.error("CRC32 mismatch at sequence \(chunk.sequenceNumber): expected \(expectedCRC), computed \(computedCRC)")
                state.withLock { $0.dataContinuation?.finish() }
                try? await handle.close()
                return
            }
        }

        // 압축 협상이 zstd 면 wire bytes 를 먼저 decompress.
        let payload: Data
        do {
            payload = try decompressIfNeeded(chunk.data)
        } catch {
            logger.error("Decompression failed at sequence \(chunk.sequenceNumber): \(error)")
            state.withLock { $0.dataContinuation?.finish() }
            try? await handle.close()
            return
        }

        let isEof = chunk.isEof
        let dataCount = payload.count

        let overflow: TransferChannelError? = state.withLock { state in
            let newTotal = state.receivedTotalBytes + UInt64(dataCount)
            if let declared = state.startNotification?.totalSize, declared > 0, newTotal > declared {
                state.transferError = .totalSizeExceeded(expected: declared, received: newTotal)
                state.dataContinuation?.finish()
                return state.transferError
            }
            state.receivedTotalBytes = newTotal
            state.dataContinuation?.yield(payload)
            state.expectedSequenceNumber += 1
            return nil
        }

        if let error = overflow {
            logger.error("\(error.description) - closing channel")
            try? await handle.close()
            return
        }

        // EOF 처리
        if isEof {
            handleTransferComplete()
            try? await handle.close()
        }
    }

    private func handleTransferComplete() {
        let (notification, receivedBytes) = state.withLock { state -> (TransferStartNotification?, UInt64) in
            state.isCompleted = true
            return (state.startNotification, state.receivedTotalBytes)
        }

        // totalSize 검증. 불일치 시 transferError를 기록하여 소비자가 결과를 폐기하도록 한다.
        // totalSize == 0 은 "알 수 없음"을 의미하며 크기 검증을 스킵한다.
        if let notification = notification, notification.totalSize > 0 {
            if receivedBytes != notification.totalSize {
                state.withLock { state in
                    state.transferError = .totalSizeMismatch(
                        expected: notification.totalSize,
                        received: receivedBytes
                    )
                }
                logger.error("Total size mismatch at EOF: expected \(notification.totalSize), received \(receivedBytes)")
            }
        }

        state.withLock { $0.dataContinuation?.finish() }
        logger.info("Transfer completed: received \(receivedBytes) bytes")
    }

    // MARK: - 송신

    /// sender 측에서 첫 메시지 (TransferStartNotification) 를 emit 하기 전에 TransferReady 도착을 await.
    private func awaitTransferReadyForSender() async throws {
        guard shouldSend() else { return }
        let alreadyReady = state.withLock { $0.transferReadySettled }
        if alreadyReady { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [state] in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    state.withLock { $0.transferReadyAwaiter = cont }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw TransferChannelError.transferReadyTimeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func compressIfNeeded(_ data: Data) throws -> Data {
        let method = state.withLock { $0.negotiatedCompression }
        switch method {
        case .zstd:
            return try ZstdCodec.compress(data)
        default:
            return data
        }
    }

    private func decompressIfNeeded(_ data: Data) throws -> Data {
        let method = state.withLock { $0.negotiatedCompression }
        switch method {
        case .zstd:
            return try ZstdCodec.decompress(data)
        default:
            return data
        }
    }

    /// 전송 시작 알림을 전송합니다.
    func sendStartNotification(_ notification: TransferStartNotification) async throws {
        guard shouldSend() else {
            logger.error("Cannot send on a receive-only channel")
            return
        }
        try await awaitTransferReadyForSender()
        try await handle.send(opcode: .transferStartNotification, message: notification)
    }

    /// 단일 청크를 전송합니다. 스트리밍 송신 시 사용.
    func writeChunk(_ chunkData: Data, isEof: Bool) async throws {
        guard shouldSend() else {
            logger.error("Cannot write on a receive-only channel")
            return
        }

        // 압축 적용 후 wire bytes 산출 → CRC32 는 wire bytes 기준.
        let wireData = try compressIfNeeded(chunkData)
        let crc = CRC32Util.compute(wireData)

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
            data: wireData,
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
        let (completed, awaiter) = state.withLock { state -> (Bool, CheckedContinuation<Void, Error>?) in
            state.dataContinuation?.finish()
            let cont = state.transferReadyAwaiter
            state.transferReadyAwaiter = nil
            return (state.isCompleted, cont)
        }
        awaiter?.resume(throwing: ChannelError.invalidFrame)
        if !completed {
            logger.warning("Stream closed before transfer completed")
        }
    }

    func handleError(error: any Error) async {
        logger.error("Stream error: \(error)")
        let awaiter = state.withLock { state -> CheckedContinuation<Void, Error>? in
            state.dataContinuation?.finish()
            let cont = state.transferReadyAwaiter
            state.transferReadyAwaiter = nil
            return cont
        }
        awaiter?.resume(throwing: error)
    }
}

// MARK: - Factory

extension TransferChannel {
    static func createIfAccepts(
        handle: ChannelHandle,
        args: [String]
    ) async throws -> ChannelCreationResult {
        let argsSet: TransferChannelArgumentsSet
        do {
            argsSet = try TransferChannelArgumentsSet.parse(from: args)
        } catch {
            return .rejected(code: -1, reason: "Invalid arguments for transfer channel: \(error)")
        }

        guard TransferChannel.accepts(argsSet, direction: handle.direction) else {
            return .rejected(code: -1, reason: "Unacceptable arguments for transfer channel")
        }

        let transferChannel = TransferChannel(handle: handle)
        try await transferChannel.prepare(argsSet)

        return .accepted(transferChannel)
    }
}
