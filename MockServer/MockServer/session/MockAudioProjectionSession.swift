//
//  MockAudioProjectionSession.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import CoreMedia

import SiriusKit

/// 파일 기반 오디오 프로젝션 세션.
/// FileAudioReader에서 샘플을 읽고 → OpusAudioEncoder로 인코딩 → ProjectionDataChannel로 전송.
class MockAudioProjectionSession: Identifiable {
    private let logger = SiriusLogger(category: "MockAudioProjectionSession", subsystem: "app.noctiluca.mockserver")

    let id: UUID
    let dataChannel: ProjectionDataChannel
    let sourceURL: URL
    let codec: AudioCodec

    private var reader: FileAudioReader?
    private var encoder: (any AudioEncoder)?

    private let frameQueue = FrameQueue<EncodedAudioFrame>(capacity: 4)

    private var readerLoopTask: Task<Void, Never>?
    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?

    private var isStopped = false

    init(id: UUID, dataChannel: ProjectionDataChannel, sourceURL: URL, codec: AudioCodec) {
        self.id = id
        self.dataChannel = dataChannel
        self.sourceURL = sourceURL
        self.codec = codec
    }

    func prepare() async throws {
        let reader = FileAudioReader(url: sourceURL)
        try await reader.prepare()
        self.reader = reader

        let encoder = OpusAudioEncoder()
        try encoder.prepare(with: AudioEncoderConfiguration(
            codec: codec,
            inputFormatDescription: nil
        ))
        self.encoder = encoder
    }

    func start() async throws {
        guard let encoder = self.encoder else {
            throw AudioEncoderError.notPrepared
        }
        try encoder.start()

        // Encoder event loop: encoder -> frameQueue
        self.encoderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for await event in encoder.events {
                switch event {
                case .frameEncoded(let encodedFrame):
                    await self.frameQueue.enqueue(encodedFrame)
                case .errorOccurred(let error):
                    self.logger.error("Audio encoder error: \(error)")
                    throw error
                case .stopped:
                    return
                }
            }
        }

        // Sender loop: frameQueue -> dataChannel (프레임 단위 실시간 페이싱)
        // Opus 인코더는 20ms(960 samples @ 48kHz) 단위로 프레임을 생산하지만,
        // AVFoundation이 가변 크기 청크를 반환하기 때문에 encoder가 여러 프레임을 한꺼번에
        // 생산할 수 있다. sender에서 프레임 간 간격을 두어 클라이언트 버퍼 오버플로우를 방지한다.
        self.senderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Opus: 960 samples @ 48kHz = 20ms per frame
            let frameDuration = Duration.milliseconds(20)
            let maxDriftThreshold = Duration.milliseconds(150)

            var nextSendTime: ContinuousClock.Instant? = nil

            while !Task.isCancelled {
                let frame: EncodedAudioFrame
                do {
                    frame = try await self.frameQueue.next()
                } catch is CancellationError {
                    return
                }

                // 페이싱: 다음 전송 시간까지 대기
                if let sendTime = nextSendTime {
                    let now = ContinuousClock.now
                    if sendTime > now {
                        do {
                            try await Task.sleep(until: sendTime, clock: .continuous)
                        } catch is CancellationError {
                            return
                        }
                    } else if now - sendTime > maxDriftThreshold {
                        // 큐가 비어 대기하다 복귀한 경우 등 — 타이밍 리셋
                        nextSendTime = nil
                    }
                }

                try await self.dataChannel.send(audioFrame: frame)

                // 다음 전송 시간 갱신
                if let sendTime = nextSendTime {
                    nextSendTime = sendTime + frameDuration
                } else {
                    nextSendTime = ContinuousClock.now + frameDuration
                }
            }
        }

        // Reader loop: reader -> encoder (절대 시간 기준 실시간 페이싱)
        guard let reader = self.reader else { return }
        let sampleRate = reader.sampleRate

        self.readerLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // 드리프트가 이 임계값을 초과하면 따라잡기(burst) 대신 타이밍 베이스라인을 리셋한다.
            // EOF 재시작이나 일시적인 인코딩 지연 등으로 인한 burst 현상을 방지.
            let maxDriftThreshold = Duration.milliseconds(150)

            var startTime = ContinuousClock.now
            var totalSamplesRead: Int64 = 0

            while !Task.isCancelled {
                do {
                    let sampleBuffer = try await reader.readNextSample()
                    let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
                    try encoder.encode(sampleBuffer: sampleBuffer)

                    totalSamplesRead += Int64(sampleCount)

                    // 절대 시간 기준 페이싱: 시작 시점 + 누적 오디오 재생 시간까지 대기
                    let expectedElapsed = Duration.microseconds(Int64(Double(totalSamplesRead) / sampleRate * 1_000_000))
                    let targetTime = startTime + expectedElapsed
                    let now = ContinuousClock.now

                    if targetTime > now {
                        try await Task.sleep(until: targetTime, clock: .continuous)
                    } else {
                        let drift = now - targetTime
                        if drift > maxDriftThreshold {
                            self.logger.warning(
                                "Audio pacing drift (\(drift)) exceeds threshold (\(maxDriftThreshold)), resetting timing baseline"
                            )
                            startTime = now
                            totalSamplesRead = 0
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.logger.error("Audio reader loop error: \(error)")
                    try? await Task.sleep(for: .milliseconds(100))

                    // 에러 복구 후 타이밍 베이스라인 리셋 (burst 방지)
                    startTime = ContinuousClock.now
                    totalSamplesRead = 0
                }
            }
        }

        logger.info("MockAudioProjectionSession \(self.id) started")
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

        logger.info("MockAudioProjectionSession \(self.id) stopped")
    }

    deinit {
        readerLoopTask?.cancel()
        encoderEventLoopTask?.cancel()
        senderEventLoopTask?.cancel()
        try? encoder?.stop()
    }
}
