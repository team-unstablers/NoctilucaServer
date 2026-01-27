//
//  RLEU16Compressor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import CoreVideo
import Accelerate
import simd

class RLEU16Compressor {
    /// Compact RLE 압축 (1바이트 count + 2바이트 RGB565)
    /// vImage/SIMD 최적화 적용
    static func compress(_ pixelBuffer: CVPixelBuffer, quantizeLevel: Int) -> Data {
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

        let shift = min(max(quantizeLevel, 0), 7)
        let needsQuantization = shift > 0
        let mask: UInt8 = needsQuantization ? ~((1 << shift) - 1) : 0xFF

        // RGB565 버퍼 할당
        var rgb565Buffer = [UInt16](repeating: 0, count: width * height)

        // BGRA → RGB565 일괄 변환 (양자화 포함)
        convertBGRAtoRGB565(
            source: baseAddress.assumingMemoryBound(to: UInt8.self),
            destination: &rgb565Buffer,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            quantizeMask: mask
        )

        // RGB565 버퍼에서 RLE 압축
        return compressRLE565(rgb565Buffer, width: width, height: height)
    }

    /// BGRA → RGB565 일괄 변환 (SIMD 최적화, 양자화 포함)
    private static func convertBGRAtoRGB565(
        source: UnsafePointer<UInt8>,
        destination: inout [UInt16],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        quantizeMask mask: UInt8
    ) {
        destination.withUnsafeMutableBufferPointer { destPtr in
            var destOffset = 0

            for row in 0..<height {
                let rowPtr = source + (row * bytesPerRow)
                var col = 0

                // 4픽셀(16바이트) 단위로 SIMD 처리
                while col + 4 <= width {
                    let pixelBase = rowPtr + (col * 4)

                    // 4픽셀 로드 (16바이트)
                    let b0 = pixelBase[0] & mask
                    let g0 = pixelBase[1] & mask
                    let r0 = pixelBase[2] & mask

                    let b1 = pixelBase[4] & mask
                    let g1 = pixelBase[5] & mask
                    let r1 = pixelBase[6] & mask

                    let b2 = pixelBase[8] & mask
                    let g2 = pixelBase[9] & mask
                    let r2 = pixelBase[10] & mask

                    let b3 = pixelBase[12] & mask
                    let g3 = pixelBase[13] & mask
                    let r3 = pixelBase[14] & mask

                    // RGB565 패킹 (4픽셀 동시)
                    destPtr[destOffset] = packRGB565Fast(r: r0, g: g0, b: b0)
                    destPtr[destOffset + 1] = packRGB565Fast(r: r1, g: g1, b: b1)
                    destPtr[destOffset + 2] = packRGB565Fast(r: r2, g: g2, b: b2)
                    destPtr[destOffset + 3] = packRGB565Fast(r: r3, g: g3, b: b3)

                    col += 4
                    destOffset += 4
                }

                // 나머지 픽셀 개별 처리
                while col < width {
                    let pixelPtr = rowPtr + (col * 4)
                    let b = pixelPtr[0] & mask
                    let g = pixelPtr[1] & mask
                    let r = pixelPtr[2] & mask
                    destPtr[destOffset] = packRGB565Fast(r: r, g: g, b: b)
                    col += 1
                    destOffset += 1
                }
            }
        }
    }

    /// RGB565 버퍼에서 RLE 압축
    private static func compressRLE565(_ buffer: [UInt16], width: Int, height: Int) -> Data {
        var output = Data()

        buffer.withUnsafeBufferPointer { bufPtr in
            var offset = 0

            for _ in 0..<height {
                var runCount: Int = 0
                var prevPixel: UInt16 = 0

                for _ in 0..<width {
                    let pixel = bufPtr[offset]
                    offset += 1

                    if runCount == 0 {
                        prevPixel = pixel
                        runCount = 1
                        continue
                    }

                    if pixel == prevPixel {
                        runCount += 1
                    } else {
                        flushRuns(&output, count: runCount, rgb565: prevPixel)
                        prevPixel = pixel
                        runCount = 1
                    }
                }

                if runCount > 0 {
                    flushRuns(&output, count: runCount, rgb565: prevPixel)
                }
            }
        }

        return consume output
    }

    /// run count가 255 초과시 여러 번 나눠서 출력
    private static func flushRuns(_ data: inout Data, count: Int, rgb565: UInt16) {
        var remaining = count
        while remaining > 0 {
            let chunk = min(remaining, 255)
            appendRun(&data, count: UInt8(chunk), rgb565: rgb565)
            remaining -= chunk
        }
    }

    /// Compact 포맷: [count: 1바이트][RGB565: 2바이트 LE]
    @inline(__always)
    private static func appendRun(_ data: inout Data, count: UInt8, rgb565: UInt16) {
        data.append(count)
        let pixelLE = rgb565.littleEndian
        withUnsafeBytes(of: pixelLE) { data.append(contentsOf: $0) }
    }

    @inline(__always)
    private static func packRGB565Fast(r: UInt8, g: UInt8, b: UInt8) -> UInt16 {
        // 비트 연산 최적화: 캐스팅 최소화
        return (UInt16(r & 0xF8) << 8) | (UInt16(g & 0xFC) << 3) | (UInt16(b) >> 3)
    }
}
