//
//  RLECompressor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import CoreVideo
import SiriusKit

protocol RLECompressor {
    static func compress(_ pixelBuffer: CVPixelBuffer) -> Data
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

func rleCompress(_ pixelBuffer: CVPixelBuffer, colorFormat: CodecOptionValue) throws -> Data {
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    guard format == kCVPixelFormatType_32BGRA else {
        throw RLECompressorError.unsupportedPixelFormat(format)
    }

    if colorFormat == .kColorFormatRGB565 {
        return RLEU16Compressor.compress(pixelBuffer)
    }

    return RLEU32Compressor.compress(pixelBuffer)
}

class RLEU32Compressor {
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
        
        let pixelBytes = baseAddress.assumingMemoryBound(to: UInt32.self)
        var output = Data() // FIXME: preallocate?
        
        for row in 0..<height {
            let stride = bytesPerRow / MemoryLayout<UInt32>.stride
            let rowPtr = pixelBytes + (row * stride)
            
            var runCount: UInt32 = 0
            var prevPixel: UInt32 = 0
           
            for col in 0..<width {
                let pixelPtr = rowPtr + col
                
                let pixel = pixelPtr.pointee
                
                if runCount == 0 {
                    prevPixel = pixel
                    runCount = 1
                    continue
                }
                
                if pixel == prevPixel && runCount < UInt32.max {
                    runCount &+= 1
                } else {
                    appendRun(&output, count: runCount, bgra32: prevPixel)
                    prevPixel = pixel
                    runCount = 1
                }
            }
            
            if runCount > 0 {
                appendRun(&output, count: runCount, bgra32: prevPixel)
            }
        }
        
        return consume output
    }
    
    
    static func appendRun(_ data: inout Data, count: UInt32, bgra32: UInt32) {
        let countLE = count.littleEndian
        withUnsafeBytes(of: countLE) { data.append(contentsOf: $0) }
        
        withUnsafeBytes(of: bgra32) { pixelPtr in
            pixelPtr.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: 4) { bytePtr in
                data.append(bytePtr, count: 3)
            }
        }
    }
}
