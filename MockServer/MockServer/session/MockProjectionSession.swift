//
//  MockProjectionSession.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
@preconcurrency import CoreMedia

import SiriusKit

/// 파일 기반 비디오 프로젝션 세션.
/// FileVideoReader에서 프레임을 읽고 → VTVideoEncoder로 인코딩 → ProjectionDataChannel로 전송.
actor MockProjectionSession: @preconcurrency Identifiable {
    private let logger = SiriusLogger(category: "MockProjectionSession", subsystem: "app.noctiluca.mockserver")

    nonisolated let id: UUID
    nonisolated let dataChannel: ProjectionDataChannel
    nonisolated let sourceURL: URL
    nonisolated let codec: Codec

    private var reader: FileVideoReader?
    private var encoder: (any VideoEncoder)?

    nonisolated let frameQueue = FrameQueue<EncodedFrame>(capacity: 8)

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

        let dataChannel = self.dataChannel
        let frameQueue = self.frameQueue
        let logger = self.logger

        // Encoder event loop: encoder -> frameQueue
        self.encoderEventLoopTask = Task.detached(priority: .userInitiated) {
            for await event in encoder.events {
                switch event {
                case .parameterSetChanged(let parameterSetMessage):
                    dataChannel.send(parameterSetMessage: parameterSetMessage)
                case .frameEncoded(let encodedFrame):
                    await frameQueue.enqueue(encodedFrame)
                case .frameSkipped:
                    break
                case .errorOccurred(let error):
                    logger.error("Encoder error: \(error)")
                    throw error
                case .stopped:
                    return
                }
            }
        }

        // Sender loop: frameQueue -> dataChannel
        self.senderEventLoopTask = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                let frame: EncodedFrame
                do {
                    frame = try await frameQueue.next()
                } catch is CancellationError {
                    return
                }
                dataChannel.send(videoFrame: frame)
            }
        }

        // Reader loop: reader -> encoder (절대 시간 기준 실시간 페이싱)
        guard let reader = self.reader else { return }
        let nominalFrameRate = await reader.nominalFrameRate
        let frameRate = max(Double(nominalFrameRate), 1.0)
        let frameDurationNs = Int64((1.0 / frameRate) * 1_000_000_000.0)
        let frameDuration = Duration.nanoseconds(frameDurationNs)

        self.readerLoopTask = Task.detached(priority: .userInitiated) {
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
                    logger.error("Reader loop error: \(error)")
                    try? await Task.sleep(for: .milliseconds(100))
                    nextFrameTime = ContinuousClock.now
                }
            }
        }

        logger.info("MockProjectionSession \(self.id) started (fps=\(nominalFrameRate))")
    }

    func stop() async {
        guard !isStopped else { return }
        isStopped = true

        readerLoopTask?.cancel()
        readerLoopTask = nil

        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil

        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil

        await frameQueue.clear()
        await frameQueue.cancelWaiter()

        await reader?.stop()
        try? encoder?.stop()

        logger.info("MockProjectionSession \(self.id) stopped")
    }
}
