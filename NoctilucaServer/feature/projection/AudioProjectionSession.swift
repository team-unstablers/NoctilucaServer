//
//  AudioProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Combine

import CoreGraphics
import CoreMedia

import SiriusKit

class AudioProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "AudioProjectionSession")

    private let recorderQueue = DispatchQueue(
        label: "app.noctiluca.server.projection.recorder.audio",
        qos: .userInitiated
    )

    let id: UUID
    let dataChannel: ProjectionDataChannel

    private var recorderArgs: AudioRecorderArgs!

    var recorder: any AudioRecorder
    var encoder: (any AudioEncoder)?
    var codec: SiriusKit.AudioCodec?
    
    private let frameQueue = FrameQueue<EncodedAudioFrame>(capacity: 4)

    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?

    private var screenLockCancellable: AnyCancellable?
    private var isReconfiguring = false
    private var isStopped = false

    init(id: UUID, dataChannel: ProjectionDataChannel) {
        self.id = id

        self.dataChannel = dataChannel
        self.recorder = ScreenCaptureKitAudioRecorder(queue: recorderQueue)

        self.recorder.delegate = self
    }

    private func reconfigureRecorder() async {
        guard !isReconfiguring else {
            logger.info("reconfigureRecorder(): already in progress, skipping")
            return
        }
        guard !isStopped else { return }

        isReconfiguring = true
        defer { isReconfiguring = false }

        let maxRetries = 2
        var lastError: Error? = nil

        // 기존 recorder 중지
        try? await self.recorder.stop()
        self.recorder.delegate = nil

        for attempt in 0...maxRetries {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(500 * attempt))
                guard !isStopped else { return }
            }

            let newRecorder = ScreenCaptureKitAudioRecorder(queue: recorderQueue)
            newRecorder.delegate = self
            self.recorder = newRecorder

            do {
                try await self.recorder.prepare(with: recorderArgs)
                try await self.recorder.start()
                logger.info("reconfigureRecorder(): succeeded (attempt \(attempt))")
                return
            } catch {
                lastError = error
                logger.warning("reconfigureRecorder(): attempt \(attempt) failed: \(error)")
                try? await self.recorder.stop()
            }
        }

        // 모든 재시도 실패
        logger.error("reconfigureRecorder(): all retries exhausted for audio projection session \(self.id)")
        dataChannel.projectionDelegate?.projectionDataChannel(
            dataChannel,
            didEncounterError: lastError ?? AudioRecorderPrepareError.internalError
        )
    }

    private func encoderEventLoopMain() async throws {
        guard let encoder = self.encoder else {
            logger.error("Encoder is not set")
            return
        }

        for await event in encoder.events {
            switch event {
            case .frameEncoded(let encodedFrame):
                try await processEncodedFrame(encodedFrame)
            case .errorOccurred(let error):
                self.logger.error("Encoder error occurred in audio projection session \(self.id): \(error)")
                throw error
            case .stopped:
                return
            }
        }
    }

    private func processEncodedFrame(_ frame: consuming EncodedAudioFrame) async throws {
        await frameQueue.enqueue(frame)
    }
    
    private func senderEventLoopMain() async throws {
        while !Task.isCancelled {
            let frame: EncodedAudioFrame
            do {
                frame = try await frameQueue.next()
            } catch is CancellationError {
                return
            }
            
            try await self.dataChannel.send(audioFrame: frame)
        }
    }

    private func handleLoopFailure(loopName: String, error: any Error) {
        guard !(error is CancellationError) else {
            return
        }

        self.logger.warning("Audio projection session \(self.id) \(loopName) loop failed: \(error)")

        self.dataChannel.projectionDelegate?.projectionDataChannel(
            self.dataChannel,
            didEncounterError: error
        )
    }

    func prepare(_ request: AudioProjectionRequest, codec: SiriusKit.AudioCodec) async throws {
        // Convert AudioSource to AudioRecorderSource
        let recorderSource: AudioRecorderSource
        switch request.source {
        case .sessionAudio:
            recorderSource = .desktopSession
        case .applicationAudio(let pid, let bundleID):
            if let pid = pid {
                recorderSource = .applicationAudioPID(pid: pid_t(pid))
            } else if let bundleID = bundleID {
                recorderSource = .applicationAudioBundleID(bundleID: bundleID)
            } else {
                recorderSource = .desktopSession
            }
        case .microphone(let deviceID):
            if let deviceID = deviceID {
                recorderSource = .microphone(deviceID: deviceID)
            } else {
                recorderSource = .desktopSession
            }
        }

        let recorderArgs = AudioRecorderArgs(
            source: recorderSource,
            codec: codec
        )

        try await self.recorder.prepare(with: recorderArgs)

        self.recorderArgs = recorderArgs
        self.codec = codec

        // 화면 잠금 구독 (최초 prepare 시에만 설정)
        if screenLockCancellable == nil {
            screenLockCancellable = await ScreenLockObserver.shared.$isScreenLocked
                .receive(on: RunLoop.main)
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] isLocked in
                    Task {
                        await self?.reconfigureRecorder()
                    }
                }
        }

        // Cancel existing encoder event loop task and clean up encoder
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil
        
        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil
        await frameQueue.clear()
        await frameQueue.cancelWaiter()
        
        try? self.encoder?.stop()

        // Create appropriate encoder based on codec
        switch codec.fourCC {
        case .opus:
            self.encoder = OpusAudioEncoder()
        case .pcmu, .pcma:
            self.encoder = PCMAudioEncoder()
        default:
            logger.warning("Unsupported audio codec: \(codec.fourCC.stringRepresentation), falling back to Opus")
            self.encoder = OpusAudioEncoder()
        }

        try self.encoder?.prepare(with: AudioEncoderConfiguration(
            codec: codec,
            inputFormatDescription: nil
        ))

        self.encoderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.encoderEventLoopMain()
            } catch {
                self.handleLoopFailure(loopName: "encoder", error: error)
            }
        }

        self.senderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.senderEventLoopMain()
            } catch {
                self.handleLoopFailure(loopName: "sender", error: error)
            }
        }
    }

    func start() async throws {
        do {
            try await self.recorder.start()
            try self.encoder?.start()
        } catch {
            self.logger.error("Failed to start audio projection session \(self.id): \(error)")
            await self.stop()
            throw error
        }
    }

    func stop() async {
        guard !isStopped else { return }

        // Stop sequence 시작 시점에 종료 상태를 먼저 표시해 재구성 경로를 차단한다.
        isStopped = true

        // 1. Task 취소 (새로운 프레임 처리 중단)
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil

        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil

        // 2. Combine 구독 취소
        screenLockCancellable?.cancel()
        screenLockCancellable = nil

        // 3. Frame queue 정리
        await frameQueue.clear()
        await frameQueue.cancelWaiter()

        // 4. Recorder 정리 (캡처 중지)
        recorder.delegate = nil
        do {
            try await self.recorder.stop()
        } catch {
            self.logger.error("Failed to stop recorder for audio projection session \(self.id): \(error)")
        }

        // 5. Encoder 정리
        do {
            try self.encoder?.stop()
        } catch {
            self.logger.error("Failed to stop encoder for audio projection session \(self.id): \(error)")
        }

        // 6. Data channel 정리
        do {
            try await self.dataChannel.close()
        } catch {
            self.logger.warning("Failed to close projection data channel \(self.dataChannel.identifier): \(error)")
        }
    }

    deinit {
        // 동기 작업 수행
        encoderEventLoopTask?.cancel()
        senderEventLoopTask?.cancel()
        screenLockCancellable?.cancel()
        recorder.delegate = nil
        try? encoder?.stop()

        // Safety-net: stop() 미호출 시 async 리소스를 비동기적으로 정리
        guard !isStopped else { return }

        logger.warning("AudioProjectionSession \(self.id) deallocated without explicit stop() - triggering safety-net async cleanup")

        let recorder = self.recorder
        let dataChannel = self.dataChannel
        let frameQueue = self.frameQueue

        Task.detached {
            await frameQueue.cancelWaiter()
            try? await recorder.stop()
            try? await dataChannel.close()
        }
    }
}

extension AudioProjectionSession: AudioRecorderDelegate {
    func audioRecorderDidStart(_ recorder: any AudioRecorder) {
        self.logger.info("audio recorder started for audio projection session \(self.id)")
    }

    func audioRecorder(_ recorder: any AudioRecorder, didStopWithError error: (any Error)?) {
        self.logger.info("audio recorder stopped for audio projection session \(self.id), error: \(String(describing: error))")

        if error != nil, !isStopped {
            Task {
                await self.reconfigureRecorder()
            }
        }
    }

    func audioRecorder(_ recorder: any AudioRecorder, didCaptureFrame frameData: CMSampleBuffer) {
        guard let encoder = self.encoder else {
            return
        }

        do {
            try encoder.encode(sampleBuffer: frameData)
        } catch {
            logger.error("Failed to encode audio frame: \(error)")
        }
    }
}
