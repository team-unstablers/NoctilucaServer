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

    private let recorderQueue: DispatchQueue = .global(qos: .userInteractive)

    let id: UUID
    let dataChannel: ProjectionDataChannel

    private var recorderArgs: AudioRecorderArgs!

    var recorder: any AudioRecorder
    var encoder: (any AudioEncoder)?
    var codec: SiriusKit.AudioCodec?
    
    private let frameQueue = FrameQueue<EncodedAudioFrame>(capacity: 4)

    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?

    init(id: UUID, dataChannel: ProjectionDataChannel) {
        self.id = id

        self.dataChannel = dataChannel
        self.recorder = ScreenCaptureKitAudioRecorder(queue: recorderQueue)

        self.recorder.delegate = self
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

        self.encoderEventLoopTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.encoderEventLoopMain()
            } catch {
                self.handleLoopFailure(loopName: "encoder", error: error)
            }
        }
        
        self.senderEventLoopTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.senderEventLoopMain()
            } catch {
                self.handleLoopFailure(loopName: "sender", error: error)
            }
        }
    }

    func start() async throws {
        try await self.recorder.start()
        try self.encoder?.start()
    }

    func stop() async {
        // Cancel task
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil
        
        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil
        await frameQueue.clear()
        await frameQueue.cancelWaiter()

        // Clean up recorder/encoder
        try? await self.recorder.stop()
        try? self.encoder?.stop()
        
        try? await self.dataChannel.close()
    }

    deinit {
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil

        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil

        recorder.delegate = nil

        // encoder.stop()은 동기 메서드이므로 직접 호출 (Task 불필요)
        try? encoder?.stop()

        // recorder.stop()은 async이므로 fire-and-forget Task가 불가피
        let frameQueue = self.frameQueue
        let recorder = recorder
        let dataChannel = self.dataChannel
        Task {
            try? await recorder.stop()
            await frameQueue.cancelWaiter()
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
