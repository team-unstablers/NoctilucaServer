//
//  RLECompressor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import CoreVideo
import SiriusKit
import simd

protocol RLECompressor {
    static func compress(_ pixelBuffer: CVPixelBuffer, quantizeLevel: Int) -> Data
}

// MARK: - SIMD Quantization

/// SIMD를 사용하여 버퍼 전체에 양자화(비트 마스킹) 적용
/// - Parameters:
///   - buffer: 양자화할 버퍼 (in-place 수정)
///   - count: 버퍼의 바이트 수
///   - mask: 적용할 비트 마스크
@inline(__always)
func applyQuantizationSIMD(
    _ buffer: UnsafeMutablePointer<UInt8>,
    count: Int,
    mask: UInt8
) {
    let maskVector = SIMD32<UInt8>(repeating: mask)
    var offset = 0

    // 32바이트 단위로 SIMD 처리
    while offset + 32 <= count {
        let ptr = buffer + offset
        ptr.withMemoryRebound(to: SIMD32<UInt8>.self, capacity: 1) { simdPtr in
            simdPtr.pointee &= maskVector
        }
        offset += 32
    }

    // 나머지 바이트는 개별 처리
    while offset < count {
        buffer[offset] &= mask
        offset += 1
    }
}

enum RLECompressorError: LocalizedError {
    case unsupportedPixelFormat(OSType)

    var errorDescription: String? {
        switch self {
        case .unsupportedPixelFormat(let format):
            return "Unsupported pixel format: \(format)"
        }
    }
}

func rleCompress(
    _ pixelBuffer: CVPixelBuffer,
    colorFormat: CodecOptionValue,
    quantizeLevel: Int = 2
) throws -> Data {
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    guard format == kCVPixelFormatType_32BGRA else {
        throw RLECompressorError.unsupportedPixelFormat(format)
    }

    if colorFormat == .kColorFormatRGB565 {
        return RLEU16Compressor.compress(pixelBuffer, quantizeLevel: quantizeLevel)
    }

    return RLEU32Compressor.compress(pixelBuffer, quantizeLevel: quantizeLevel)
}

class RLEU32Compressor {
    /// Compact RLE 압축 (1바이트 count + 3바이트 RGB)
    /// SIMD 양자화 최적화 적용
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

        // 양자화가 필요한 경우 SIMD 처리를 위해 복사
        var quantizedBuffer: [UInt8]?
        let pixelBytes: UnsafePointer<UInt8>

        if needsQuantization {
            // 타일 데이터 복사 후 SIMD 양자화 적용
            let totalBytes = height * bytesPerRow
            quantizedBuffer = [UInt8](repeating: 0, count: totalBytes)
            quantizedBuffer!.withUnsafeMutableBufferPointer { destPtr in
                memcpy(destPtr.baseAddress!, baseAddress, totalBytes)
                applyQuantizationSIMD(destPtr.baseAddress!, count: totalBytes, mask: mask)
            }
            pixelBytes = quantizedBuffer!.withUnsafeBufferPointer { $0.baseAddress! }
        } else {
            pixelBytes = UnsafePointer(baseAddress.assumingMemoryBound(to: UInt8.self))
        }

        var output = Data()

        for row in 0..<height {
            let rowPtr = pixelBytes + (row * bytesPerRow)

            var runCount: Int = 0
            var prevB: UInt8 = 0
            var prevG: UInt8 = 0
            var prevR: UInt8 = 0

            for col in 0..<width {
                let pixelPtr = rowPtr + (col * 4)

                let b = pixelPtr[0]
                let g = pixelPtr[1]
                let r = pixelPtr[2]

                if runCount == 0 {
                    prevB = b
                    prevG = g
                    prevR = r
                    runCount = 1
                    continue
                }

                if b == prevB && g == prevG && r == prevR {
                    runCount += 1
                } else {
                    flushRuns(&output, count: runCount, b: prevB, g: prevG, r: prevR)
                    prevB = b
                    prevG = g
                    prevR = r
                    runCount = 1
                }
            }

            if runCount > 0 {
                flushRuns(&output, count: runCount, b: prevB, g: prevG, r: prevR)
            }
        }

        return consume output
    }

    /// run count가 255 초과시 여러 번 나눠서 출력
    private static func flushRuns(_ data: inout Data, count: Int, b: UInt8, g: UInt8, r: UInt8) {
        var remaining = count
        while remaining > 0 {
            let chunk = min(remaining, 255)
            appendRun(&data, count: UInt8(chunk), b: b, g: g, r: r)
            remaining -= chunk
        }
    }

    /// Compact 포맷: [count: 1바이트][B][G][R]
    @inline(__always)
    private static func appendRun(_ data: inout Data, count: UInt8, b: UInt8, g: UInt8, r: UInt8) {
        data.append(count)
        data.append(b)
        data.append(g)
        data.append(r)
    }
}
