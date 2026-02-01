//
//  RLEU32Decompressor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation

class RLEU32Decompressor {
    /// Compact RLE 해제 (1바이트 count + 3바이트 BGR)
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
        let stride = bytesPerRow / MemoryLayout<UInt32>.stride
        try output.withMemoryRebound(to: UInt32.self, capacity: 1) { output32 in
            try data.withUnsafeBytes { basePtr in
                let bytePtr = basePtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                for row in 0..<height {
                    var col = 0
                    while col < width {
                        // Compact 포맷: [count: 1바이트][B][G][R]
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
                        guard offset + 3 <= data.count else {
                            throw ZRLEVideoDecoderError.invalidTileData("rgb888 truncated")
                        }

                        // BGR -> BGRA (alpha = 0xFF)
                        let pixel = (
                            UInt32(0xFF00_0000)
                            | (UInt32(bytePtr[offset + 2]) << 16)
                            | (UInt32(bytePtr[offset + 1]) << 8)
                            | UInt32(bytePtr[offset])
                        )
                        offset += 3

                        let pixelPtr = output32 + ((originY + row) * stride) + (originX + col)
                        pixelPtr.update(repeating: pixel, count: runCount)

                        col += runCount
                    }
                }

                if offset != data.count {
                    throw ZRLEVideoDecoderError.invalidTileData("rle payload trailing bytes")
                }
            }
        }
    }
}
