//
//  FileAudioReader.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import AVFoundation
@preconcurrency import CoreMedia
import SiriusKit

/// AVAssetReader 기반 오디오 파일 읽기. 파일 끝 도달 시 자동으로 처음부터 재시작(루프).
actor FileAudioReader {
    private let logger = SiriusLogger(category: "FileAudioReader", subsystem: "app.noctiluca.mockserver")

    nonisolated let url: URL

    private(set) var sampleRate: Double = 48000.0
    private(set) var channelCount: UInt32 = 2

    private var asset: AVAsset?
    private var assetReader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?

    init(url: URL) {
        self.url = url
    }

    func prepare() async throws {
        let asset = AVURLAsset(url: url)
        self.asset = asset

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FileReaderError.noAudioTrack
        }

        try setupReader(asset: asset, track: audioTrack)

        logger.info("Prepared audio reader: \(self.url.lastPathComponent), sampleRate=\(self.sampleRate), channels=\(self.channelCount)")
    }

    private func setupReader(asset: AVAsset, track: AVAssetTrack) throws {
        let reader = try AVAssetReader(asset: asset)

        // Linear PCM Float32 non-interleaved 출력 (OpusAudioEncoder가 non-interleaved 전제로 동작)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw FileReaderError.cannotAddOutput
        }

        reader.add(output)

        guard reader.startReading() else {
            throw FileReaderError.readerStartFailed(reader.error)
        }

        self.assetReader = reader
        self.trackOutput = output
        self.sampleRate = 48000.0
        self.channelCount = 2
    }

    /// 다음 오디오 샘플을 읽는다. 파일 끝이면 자동으로 재시작하여 루프한다.
    func readNextSample() async throws -> CMSampleBuffer {
        while true {
            if let output = trackOutput,
               let sampleBuffer = output.copyNextSampleBuffer() {
                return sampleBuffer
            }

            logger.info("Reached end of audio track, restarting...")
            try await restartReader()
        }
    }

    private func restartReader() async throws {
        assetReader?.cancelReading()
        assetReader = nil
        trackOutput = nil

        guard let asset = self.asset else {
            throw FileReaderError.noAsset
        }

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FileReaderError.noAudioTrack
        }

        try setupReader(asset: asset, track: audioTrack)
    }

    func stop() {
        assetReader?.cancelReading()
        assetReader = nil
        trackOutput = nil
    }
}
