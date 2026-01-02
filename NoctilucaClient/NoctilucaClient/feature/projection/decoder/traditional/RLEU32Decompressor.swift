//
//  RLEU32Decompressor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation

class RLEU32Decompressor {
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
                for row in 0..<height {
                    var col = 0
                    while col < width {
                        guard offset + 4 <= data.count else {
                            throw ZRLEVideoDecoderError.invalidTileData("rle header truncated")
                        }
                        
                        let runCount = Int((basePtr.baseAddress! + offset).loadUnaligned(as: UInt32.self).littleEndian)
                        offset += 4
                        
                        if runCount <= 0 {
                            throw ZRLEVideoDecoderError.invalidTileData("invalid run length")
                        }
                        guard col + runCount <= width else {
                            throw ZRLEVideoDecoderError.invalidTileData("run exceeds row width")
                        }
                        guard offset + 3 <= data.count else {
                            throw ZRLEVideoDecoderError.invalidTileData("rgb888 truncated")
                        }
                        
                        let pixel = (
                            UInt32(0xFF00_0000)
                            | (UInt32(data[offset + 2]) << 16)
                            | (UInt32(data[offset + 1]) << 8)
                            | UInt32(data[offset])
                        )
                        offset += 3
                        
                        var pixelPtr = output32 + ((originY + row) * stride) + (originX + col)
                        
                        pixelPtr.update(repeating: pixel, count: runCount)
                        
                        /*
                         // 이거 memcpy스러운 무언가로 더 빠르게 할 수는 없을까?
                         for _ in 0..<runCount {
                         pixelPtr.pointee = pixel
                         pixelPtr += 1
                         }
                         */
                        col += runCount
                    }
                }
                
                if offset != data.count {
                    throw ZRLEVideoDecoderError.invalidTileData("rle payload trailing bytes")
                }
            }
        }
    }

    private static func readUInt32LE(_ data: Data, offset: inout Int) -> UInt32 {
        return data.withUnsafeBytes { basePtr in
            let ptr = basePtr.baseAddress! + offset
            
            defer { offset += 4 }
            
            return ptr.loadUnaligned(as: UInt32.self).littleEndian
        }
        /*
        let value = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        return value
         */
    }
}
