//
//  FileVideoReader.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import AVFoundation
import CoreMedia
import SiriusKit

/// AVAssetReader 기반 비디오 파일 읽기. 파일 끝 도달 시 자동으로 처음부터 재시작(루프).
class FileVideoReader {
    private let logger = SiriusLogger(category: "FileVideoReader", subsystem: "app.noctiluca.mockserver")

    let url: URL

    private(set) var naturalSize: CGSize = .zero
    private(set) var nominalFrameRate: Float = 30.0

    private var asset: AVAsset?
    private var assetReader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?

    init(url: URL) {
        self.url = url
    }

    func prepare() async throws {
        let asset = AVURLAsset(url: url)
        self.asset = asset

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw FileReaderError.noVideoTrack
        }

        let size = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)

        self.naturalSize = size
        self.nominalFrameRate = frameRate > 0 ? frameRate : 30.0

        try setupReader(asset: asset, track: videoTrack)

        logger.info("Prepared video reader: \(self.url.lastPathComponent), size=\(self.naturalSize), fps=\(self.nominalFrameRate)")
    }

    private func setupReader(asset: AVAsset, track: AVAssetTrack) throws {
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
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
    }

    /// 다음 비디오 프레임을 읽는다. 파일 끝이면 자동으로 재시작하여 루프한다.
    func readNextFrame() async throws -> CMSampleBuffer {
        while true {
            if let output = trackOutput,
               let sampleBuffer = output.copyNextSampleBuffer() {
                return sampleBuffer
            }

            // 파일 끝 도달 — 재시작
            logger.info("Reached end of video file, restarting...")
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

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw FileReaderError.noVideoTrack
        }

        try setupReader(asset: asset, track: videoTrack)
    }

    func stop() {
        assetReader?.cancelReading()
        assetReader = nil
        trackOutput = nil
    }
}

enum FileReaderError: LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case noAsset
    case cannotAddOutput
    case readerStartFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:     return "No video track found in file."
        case .noAudioTrack:     return "No audio track found in file."
        case .noAsset:          return "No asset available."
        case .cannotAddOutput:  return "Cannot add output to asset reader."
        case .readerStartFailed(let e): return "Asset reader failed to start: \(e?.localizedDescription ?? "unknown")"
        }
    }
}
