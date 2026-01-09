//
//  RLEU16Decompressor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation

class RLEU16Decompressor {
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
        for row in 0..<height {
            var col = 0
            while col < width {
                guard offset + 4 <= data.count else {
                    throw ZRLEVideoDecoderError.invalidTileData("rle header truncated")
                }
                let runCount = Int(readUInt32LE(data, offset: &offset))
                if runCount <= 0 {
                    throw ZRLEVideoDecoderError.invalidTileData("invalid run length")
                }
                guard col + runCount <= width else {
                    throw ZRLEVideoDecoderError.invalidTileData("run exceeds row width")
                }

                guard offset + 2 <= data.count else {
                    throw ZRLEVideoDecoderError.invalidTileData("rgb565 truncated")
                }
                let pixel565 = readUInt16LE(data, offset: &offset)
                let rgb = unpackRGB565(pixel565)

                var pixelPtr = output + ((originY + row) * bytesPerRow) + ((originX + col) * 4)
                for _ in 0..<runCount {
                    pixelPtr[0] = rgb.b
                    pixelPtr[1] = rgb.g
                    pixelPtr[2] = rgb.r
                    pixelPtr[3] = 0xFF
                    pixelPtr += 4
                }

                col += runCount
            }
        }

        if offset != data.count {
            throw ZRLEVideoDecoderError.invalidTileData("rle payload trailing bytes")
        }
    }

    private static func unpackRGB565(_ value: UInt16) -> (r: UInt8, g: UInt8, b: UInt8) {
        let r5 = (value >> 11) & 0x1F
        let g6 = (value >> 5) & 0x3F
        let b5 = value & 0x1F
        let r = UInt8((r5 << 3) | (r5 >> 2))
        let g = UInt8((g6 << 2) | (g6 >> 4))
        let b = UInt8((b5 << 3) | (b5 >> 2))
        return (r, g, b)
    }

    private static func readUInt16LE(_ data: Data, offset: inout Int) -> UInt16 {
        let value = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        offset += 2
        return value
    }

    private static func readUInt32LE(_ data: Data, offset: inout Int) -> UInt32 {
        let value = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        return value
    }
}
