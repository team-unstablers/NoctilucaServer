//
//  RLEU16Decompressor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import Accelerate

class RLEU16Decompressor {
    /// Compact RLE 해제 (1바이트 count + 2바이트 RGB565)
    static func apply(
        _ data: Data,
        to output: UnsafeMutablePointer<UInt8>,
        bytesPerRow: Int,
        originX: Int,
        originY: Int,
        width: Int,
        height: Int
    ) throws {
        var offset = 0
        try data.withUnsafeBytes { basePtr in
            let bytePtr = basePtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

            for row in 0..<height {
                var col = 0
                while col < width {
                    // Compact 포맷: [count: 1바이트][RGB565: 2바이트 LE]
                    guard offset + 1 <= data.count else {
                        throw ZRLEVideoDecoderError.invalidTileData("rle header truncated")
                    }

                    let runCount = Int(bytePtr[offset])
                    offset += 1

                    if runCount <= 0 {
                        throw ZRLEVideoDecoderError.invalidTileData("invalid run length")
                    }
                    guard col + runCount <= width else {
                        throw ZRLEVideoDecoderError.invalidTileData("run exceeds row width")
                    }

                    guard offset + 2 <= data.count else {
                        throw ZRLEVideoDecoderError.invalidTileData("rgb565 truncated")
                    }

                    let pixel565 = UInt16(bytePtr[offset]) | (UInt16(bytePtr[offset + 1]) << 8)
                    offset += 2

                    // RGB565 → BGRA 패킹 (UInt32로 한 번에 쓰기)
                    let bgraPixel = unpackRGB565ToBGRA(pixel565)

                    let baseOffset = ((originY + row) * bytesPerRow) + ((originX + col) * 4)
                    (output + baseOffset).withMemoryRebound(to: UInt32.self, capacity: runCount) { ptr in
                        ptr.update(repeating: bgraPixel, count: runCount)
                    }

                    col += runCount
                }
            }

            if offset != data.count {
                throw ZRLEVideoDecoderError.invalidTileData("rle payload trailing bytes")
            }
        }
    }

    /// RGB565 → BGRA (UInt32) 변환
    /// 메모리 레이아웃: [B, G, R, A] (Little Endian에서 0xAARRGGBB)
    @inline(__always)
    private static func unpackRGB565ToBGRA(_ value: UInt16) -> UInt32 {
        let r5 = (value >> 11) & 0x1F
        let g6 = (value >> 5) & 0x3F
        let b5 = value & 0x1F

        // 5/6비트 → 8비트 확장 (상위 비트 복제)
        let r = UInt32((r5 << 3) | (r5 >> 2))
        let g = UInt32((g6 << 2) | (g6 >> 4))
        let b = UInt32((b5 << 3) | (b5 >> 2))

        // BGRA 패킹: 0xAARRGGBB (Little Endian 메모리: B, G, R, A)
        return 0xFF00_0000 | (r << 16) | (g << 8) | b
    }
}
