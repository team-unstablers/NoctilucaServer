//
//  AudioProjectionSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia

import SiriusKitClient

/// Audio projection session that handles audio decoding and playback.
class AudioProjectionSession: Identifiable {
    private let logger = SiriusLogger(category: "AudioProjectionSession", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")

    let id: UUID
    weak var dataChannel: ProjectionDataChannel?
    weak var controlChannel: ProjectionChannel?

    private(set) var decoder: (any AudioDecoder)?
    private(set) var codec: SiriusKitClient.AudioCodec?

    // MARK: - AVAudioEngine

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    /// Output format for the audio engine (48kHz, stereo, Float32)
    private var outputFormat: AVAudioFormat?

    // MARK: - Buffering Control

    /// If true, buffers initial frames before starting playback.
    var enableInitialBuffering: Bool = false

    /// Number of frames to buffer before starting playback.
    var initialBufferCount: Int = 3

    private var isBuffering: Bool = false
    private var bufferedFrames: [DecodedAudioFrame] = []

    private var isStarted: Bool = false

    // MARK: - Lifecycle

    init(id: UUID, dataChannel: ProjectionDataChannel, controlChannel: ProjectionChannel) {
        self.id = id
        self.dataChannel = dataChannel
        self.controlChannel = controlChannel
    }

    deinit {
        try? stop()
    }

    /// Prepares the session with the given codec.
    func prepare(codec: SiriusKitClient.AudioCodec) async throws {
        self.codec = codec

        // Clean up existing decoder
        try? decoder?.stop()
        decoder = nil

        // Select decoder based on codec
        let selectedDecoder: any AudioDecoder
        switch codec.fourCC {
        case .pcmu, .pcma:
            selectedDecoder = PCMAudioDecoder()
        case .opus:
            selectedDecoder = OpusAudioDecoder()
        default:
            throw AudioDecoderError.unsupportedCodec(codec.fourCC.stringRepresentation)
        }

        selectedDecoder.delegate = self
        self.decoder = selectedDecoder

        // Configure decoder
        let configuration = AudioDecoderConfiguration(
            codec: codec,
            outputSampleRate: 48000,
            outputChannelCount: 2
        )
        try selectedDecoder.prepare(with: configuration)

        // Setup audio engine
        try setupAudioEngine()

        logger.info("AudioProjectionSession prepared with codec: \(codec.fourCC.stringRepresentation)")
    }

    /// Starts audio decoding and playback.
    func start() async throws {
        guard let decoder = decoder else {
            throw AudioDecoderError.notPrepared
        }
        guard let audioEngine = audioEngine,
              let playerNode = playerNode else {
            throw AudioDecoderError.notPrepared
        }

        try decoder.start()

        do {
            try audioEngine.start()
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            throw error
        }

        isStarted = true

        if enableInitialBuffering {
            isBuffering = true
            logger.info("AudioProjectionSession started (buffering mode, count: \(self.initialBufferCount))")
        } else {
            playerNode.play()
            logger.info("AudioProjectionSession started (immediate playback)")
        }
    }

    /// Stops audio decoding and playback.
    func stop() throws {
        isStarted = false

        playerNode?.stop()
        audioEngine?.stop()

        try decoder?.stop()
        decoder = nil

        bufferedFrames.removeAll()
        isBuffering = false

        logger.info("AudioProjectionSession stopped")
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        // Create output format (48kHz, stereo, Float32)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.outputFormat = format

        // Attach player node to engine
        engine.attach(player)

        // Connect player to main mixer
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Prepare the engine
        engine.prepare()

        self.audioEngine = engine
        self.playerNode = player

        logger.info("Audio engine setup complete")
    }

    // MARK: - Frame Handling

    /// Handles an encoded audio frame from the data channel.
    func handleEncodedFrame(_ frame: EncodedAudioFrameInput) {
        guard isStarted else { return }

        do {
            try decoder?.decode(frame)
        } catch {
            logger.error("Failed to decode audio frame: \(error.localizedDescription)")
        }
    }
}

// MARK: - AudioDecoderDelegate

extension AudioProjectionSession: AudioDecoderDelegate {
    func audioDecoder(_ decoder: AudioDecoder, didDecode frame: DecodedAudioFrame) {
        guard isStarted else { return }
        guard let playerNode = playerNode else { return }

        if enableInitialBuffering && isBuffering {
            // Buffering mode: accumulate frames
            bufferedFrames.append(frame)

            if bufferedFrames.count >= initialBufferCount {
                // Buffering complete - schedule all frames and start playback
                logger.info("Initial buffering complete, starting playback with \(self.bufferedFrames.count) frames")

                for buffered in bufferedFrames {
                    playerNode.scheduleBuffer(buffered.pcmBuffer)
                }
                bufferedFrames.removeAll()
                isBuffering = false
                playerNode.play()
            }
        } else {
            // Immediate playback mode
            playerNode.scheduleBuffer(frame.pcmBuffer)
        }
    }

    func audioDecoder(_ decoder: AudioDecoder, didFailWith error: Error) {
        logger.error("Audio decoder error: \(error.localizedDescription)")
    }
}

// MARK: - ProjectionDataChannelDelegate

extension AudioProjectionSession: ProjectionDataChannelDelegate {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        // Audio session ignores video frames
    }

    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveAudioFrame frame: consuming EncodedAudioFrameInput) {
        handleEncodedFrame(frame)
    }
}
