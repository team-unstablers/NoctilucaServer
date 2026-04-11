//
//  MockProjectionSession.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import CoreMedia

import SiriusKit

/// 파일 기반 비디오 프로젝션 세션.
/// FileVideoReader에서 프레임을 읽고 → VTVideoEncoder로 인코딩 → ProjectionDataChannel로 전송.
class MockProjectionSession: Identifiable {
    private let logger = SiriusLogger(category: "MockProjectionSession", subsystem: "app.noctiluca.mockserver")

    let id: UUID
    let dataChannel: ProjectionDataChannel
    let sourceURL: URL
    let codec: Codec

    private var reader: FileVideoReader?
    private var encoder: (any VideoEncoder)?

    private let frameQueue = FrameQueue<EncodedFrame>(capacity: 8)

    private var readerLoopTask: Task<Void, Never>?
    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?

    private var isStopped = false

    init(id: UUID, dataChannel: ProjectionDataChannel, sourceURL: URL, codec: Codec) {
        self.id = id
        self.dataChannel = dataChannel
        self.sourceURL = sourceURL
        self.codec = codec
    }

    func prepare() async throws {
        let reader = FileVideoReader(url: sourceURL)
        try await reader.prepare()
        self.reader = reader

        let encoder = VTVideoEncoder()
        try encoder.prepare(with: VideoEncoderConfiguration(
            codec: codec,
            inputFormatDescription: nil
        ))
        self.encoder = encoder
    }

    func start() async throws {
        guard let encoder = self.encoder else {
            throw VideoEncoderError.notPrepared
        }
        try encoder.start()

        // Encoder event loop: encoder -> frameQueue
        self.encoderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for await event in encoder.events {
                switch event {
                case .parameterSetChanged(let parameterSetMessage):
                    self.dataChannel.send(parameterSetMessage: parameterSetMessage)
                case .frameEncoded(let encodedFrame):
                    await self.frameQueue.enqueue(encodedFrame)
                case .frameSkipped:
                    break
                case .errorOccurred(let error):
                    self.logger.error("Encoder error: \(error)")
                    throw error
                case .stopped:
                    return
                }
            }
        }

        // Sender loop: frameQueue -> dataChannel
        self.senderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let frame: EncodedFrame
                do {
                    frame = try await self.frameQueue.next()
                } catch is CancellationError {
                    return
                }
                self.dataChannel.send(videoFrame: frame)
            }
        }

        // Reader loop: reader -> encoder (절대 시간 기준 실시간 페이싱)
        guard let reader = self.reader else { return }
        let frameRate = max(Double(reader.nominalFrameRate), 1.0)
        let frameDurationNs = Int64((1.0 / frameRate) * 1_000_000_000.0)
        let frameDuration = Duration.nanoseconds(frameDurationNs)

        self.readerLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var frameCounter: UInt64 = 0
            let maxDriftThreshold = Duration.milliseconds(200)
            var nextFrameTime = ContinuousClock.now

            while !Task.isCancelled {
                do {
                    let now = ContinuousClock.now
                    if nextFrameTime > now {
                        try await Task.sleep(until: nextFrameTime, clock: .continuous)
                    } else if now - nextFrameTime > maxDriftThreshold {
                        // 인코더 지연/시스템 스톨 후에는 burst 대신 기준 시각을 재설정한다.
                        nextFrameTime = now
                    }

                    let sampleBuffer = try await reader.readNextFrame()
                    try encoder.encode(
                        frameID: frameCounter,
                        sampleBuffer: sampleBuffer
                    )
                    frameCounter += 1
                    nextFrameTime += frameDuration
                } catch is CancellationError {
                    return
                } catch {
                    self.logger.error("Reader loop error: \(error)")
                    try? await Task.sleep(for: .milliseconds(100))
                    nextFrameTime = ContinuousClock.now
                }
            }
        }

        logger.info("MockProjectionSession \(self.id) started (fps=\(reader.nominalFrameRate))")
    }

    func stop() async {
        guard !isStopped else { return }
        defer { isStopped = true }

        readerLoopTask?.cancel()
        readerLoopTask = nil

        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil

        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil

        await frameQueue.clear()
        await frameQueue.cancelWaiter()

        reader?.stop()
        try? encoder?.stop()

        logger.info("MockProjectionSession \(self.id) stopped")
    }

    deinit {
        readerLoopTask?.cancel()
        encoderEventLoopTask?.cancel()
        senderEventLoopTask?.cancel()
        try? encoder?.stop()
    }
}
