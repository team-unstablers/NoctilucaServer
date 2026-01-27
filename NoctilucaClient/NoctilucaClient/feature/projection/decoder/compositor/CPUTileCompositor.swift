//
//  CPUTileCompositor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2025/01/28.
//

import Foundation
import CoreGraphics
import CoreVideo

/// CPU 기반 타일 합성기
final class CPUTileCompositor: TileCompositor {
    var frameSize: CGSize {
        didSet {
            if frameSize != oldValue {
                recreateBufferPool()
            }
        }
    }

    private var pixelBufferPool: CVPixelBufferPool?
    private var baseBuffer: CVPixelBuffer?

    init(frameSize: CGSize = .zero) {
        self.frameSize = frameSize
        if frameSize != .zero {
            recreateBufferPool()
        }
    }

    deinit {
        invalidate()
    }

    // MARK: - TileCompositor

    func composite(_ frame: DecodedTileFrame) throws -> CVPixelBuffer {
        if frameSize != frame.frameSize {
            frameSize = frame.frameSize
        }

        let outputBuffer = try acquireBuffer()

        if !frame.isKeyFrame {
            guard let baseBuffer else {
                throw TileCompositorError.missingKeyFrame
            }
            copyPixelBuffer(from: baseBuffer, to: outputBuffer)
        } else {
            clearPixelBuffer(outputBuffer)
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(outputBuffer) else {
            throw TileCompositorError.bufferAcquisitionFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        let outputWidth = CVPixelBufferGetWidth(outputBuffer)
        let outputHeight = CVPixelBufferGetHeight(outputBuffer)

        for tile in frame.tiles {
            try copyTile(
                tile,
                to: baseAddress,
                bytesPerRow: bytesPerRow,
                outputWidth: outputWidth,
                outputHeight: outputHeight
            )
        }

        baseBuffer = outputBuffer

        return outputBuffer
    }

    func reset() {
        baseBuffer = nil
    }

    func invalidate() {
        baseBuffer = nil
        pixelBufferPool = nil
    }

    // MARK: - Private

    private func recreateBufferPool() {
        guard frameSize.width > 0, frameSize.height > 0 else {
            pixelBufferPool = nil
            return
        }

        var pool: CVPixelBufferPool?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(frameSize.width),
            kCVPixelBufferHeightKey: Int(frameSize.height),
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        if status == kCVReturnSuccess {
            pixelBufferPool = pool
            baseBuffer = nil
        }
    }

    private func acquireBuffer() throws -> CVPixelBuffer {
        guard let pool = pixelBufferPool else {
            throw TileCompositorError.bufferPoolCreationFailed
        }

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)

        guard status == kCVReturnSuccess, let buffer else {
            throw TileCompositorError.bufferAcquisitionFailed
        }

        return buffer
    }

    private func copyTile(
        _ tile: DecodedTile,
        to baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        outputWidth: Int,
        outputHeight: Int
    ) throws {
        let tileX = Int(tile.rect.origin.x)
        let tileY = Int(tile.rect.origin.y)
        let tileWidth = Int(tile.rect.width)
        let tileHeight = Int(tile.rect.height)
        let tileBytesPerRow = tileWidth * 4  // BGRA

        guard tileX >= 0, tileY >= 0 else {
            throw TileCompositorError.invalidTileRect
        }
        guard tileWidth > 0, tileHeight > 0 else {
            throw TileCompositorError.invalidTileRect
        }
        guard tileX + tileWidth <= outputWidth,
              tileY + tileHeight <= outputHeight else {
            throw TileCompositorError.invalidTileRect
        }

        tile.pixelData.withUnsafeBytes { srcPtr in
            guard let srcBase = srcPtr.baseAddress else { return }

            for row in 0..<tileHeight {
                let srcOffset = row * tileBytesPerRow
                let dstOffset = (tileY + row) * bytesPerRow + tileX * 4

                memcpy(
                    baseAddress.advanced(by: dstOffset),
                    srcBase.advanced(by: srcOffset),
                    tileBytesPerRow
                )
            }
        }
    }

    private func copyPixelBuffer(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let destWidth = CVPixelBufferGetWidth(destination)
        let destHeight = CVPixelBufferGetHeight(destination)

        guard sourceWidth == destWidth, sourceHeight == destHeight else {
            clearPixelBuffer(destination)
            return
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }

        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destBase = CVPixelBufferGetBaseAddress(destination) else {
            return
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
        let bytesToCopy = min(sourceBytesPerRow, destBytesPerRow)

        for row in 0..<sourceHeight {
            let src = sourceBase.advanced(by: row * sourceBytesPerRow)
            let dst = destBase.advanced(by: row * destBytesPerRow)
            memcpy(dst, src, bytesToCopy)
        }
    }

    private func clearPixelBuffer(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        memset(base, 0, bytesPerRow * height)
    }
}
