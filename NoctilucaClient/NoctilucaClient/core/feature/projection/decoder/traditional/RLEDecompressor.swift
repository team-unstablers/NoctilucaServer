//
//  RLEDecompressor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import SiriusKitClient

func rleDecompress(
    _ data: Data,
    to output: UnsafeMutablePointer<UInt8>,
    bytesPerRow: Int,
    originX: Int,
    originY: Int,
    width: Int,
    height: Int,
    colorFormat: CodecOptionValue
) throws {
    if colorFormat == .kColorFormatRGB565 {
        try RLEU16Decompressor.apply(
            data,
            to: output,
            bytesPerRow: bytesPerRow,
            originX: originX,
            originY: originY,
            width: width,
            height: height
        )
    } else {
        try RLEU32Decompressor.apply(
            data,
            to: output,
            bytesPerRow: bytesPerRow,
            originX: originX,
            originY: originY,
            width: width,
            height: height
        )
    }
}
