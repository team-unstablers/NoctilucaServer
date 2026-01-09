//
//  RLEU16Compressor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import CoreVideo

class RLEU16Compressor {
    static func compress(_ pixelBuffer: CVPixelBuffer) -> Data {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        assert(format == kCVPixelFormatType_32BGRA, "Unsupported pixel format")

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            fatalError("Failed to get base address of pixel buffer")
        }

        let pixelBytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var output = Data() // FIXME: preallocate?

        for row in 0..<height {
            let rowPtr = pixelBytes + (row * bytesPerRow)

            var runCount: UInt32 = 0
            var prevPixel: UInt16 = 0

            for col in 0..<width {
                let pixelPtr = rowPtr + (col * 4)
                let b = pixelPtr[0]
                let g = pixelPtr[1]
                let r = pixelPtr[2]
                let pixel = packRGB565(r: r, g: g, b: b)

                if runCount == 0 {
                    prevPixel = pixel
                    runCount = 1
                    continue
                }

                if pixel == prevPixel && runCount < UInt32.max {
                    runCount &+= 1
                } else {
                    appendRun(&output, count: runCount, rgb565: prevPixel)
                    prevPixel = pixel
                    runCount = 1
                }
            }

            if runCount > 0 {
                appendRun(&output, count: runCount, rgb565: prevPixel)
            }
        }

        return consume output
    }

    private static func appendRun(_ data: inout Data, count: UInt32, rgb565: UInt16) {
        let countLE = count.littleEndian
        withUnsafeBytes(of: countLE) { data.append(contentsOf: $0) }
        let pixelLE = rgb565.littleEndian
        withUnsafeBytes(of: pixelLE) { data.append(contentsOf: $0) }
    }

    private static func packRGB565(r: UInt8, g: UInt8, b: UInt8) -> UInt16 {
        let r5 = UInt16(r >> 3)
        let g6 = UInt16(g >> 2)
        let b5 = UInt16(b >> 3)
        return (r5 << 11) | (g6 << 5) | b5
    }
}
