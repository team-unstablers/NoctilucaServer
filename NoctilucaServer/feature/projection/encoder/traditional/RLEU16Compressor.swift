//
//  RLEU16Compressor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation
import CoreVideo

class RLEU16Compressor {
    
    /// Compact RLE 압축 (최적화됨: Zero-Copy, Pointer Arithmetic)
    static func compress(_ pixelBuffer: CVPixelBuffer, quantizeLevel: Int) -> Data {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // CVPixelBuffer 잠금
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else { return Data() }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let srcPtr = srcBase.assumingMemoryBound(to: UInt8.self)
        
        // 양자화 마스크 계산
        let shift = min(max(quantizeLevel, 0), 7)
        let needsQuantization = shift > 0
        let mask: UInt8 = needsQuantization ? ~((1 << shift) - 1) : 0xFF
        
        // 출력 버퍼 예상 크기 할당
        // 최악의 경우: 모든 픽셀이 달라서 (1바이트 count + 2바이트 픽셀) * 픽셀수
        // 넉넉하게 잡고 나중에 실제 크기만큼만 복사합니다.
        let maxOutputSize = width * height * 3
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxOutputSize)
        defer { outputBuffer.deallocate() }
        
        var dstOffset = 0
        
        // 행 단위 처리
        for y in 0..<height {
            let rowStart = srcPtr + (y * bytesPerRow)
            var x = 0
            
            // RLE 상태 변수
            var runCount = 0
            var currentPixel: UInt16 = 0
            
            // 픽셀 루프
            while x < width {
                // 1. BGRA 읽기 (Pointer Arithmetic)
                let pixelPtr = rowStart + (x * 4)
                let b = pixelPtr[0] & mask
                let g = pixelPtr[1] & mask
                let r = pixelPtr[2] & mask
                
                // 2. 즉시 RGB565 변환 (Inline)
                // (R & 0xF8) << 8 | (G & 0xFC) << 3 | (B) >> 3
                let rgb565 = (UInt16(r) & 0xF8) << 8 | (UInt16(g) & 0xFC) << 3 | (UInt16(b) >> 3)
                
                // 3. RLE 로직
                if runCount == 0 {
                    currentPixel = rgb565
                    runCount = 1
                } else if rgb565 == currentPixel {
                    runCount += 1
                } else {
                    // 이전 런 플러시
                    flushRun(to: outputBuffer, offset: &dstOffset, count: runCount, pixel: currentPixel)
                    currentPixel = rgb565
                    runCount = 1
                }
                
                x += 1
            }
            
            // 행의 마지막 런 처리
            if runCount > 0 {
                flushRun(to: outputBuffer, offset: &dstOffset, count: runCount, pixel: currentPixel)
            }
        }
        
        // 결과 Data 생성 (실제 사용된 크기만큼)
        return Data(bytes: outputBuffer, count: dstOffset)
    }
    
    // Inline 최적화를 위해 @inline(__always) 사용
    @inline(__always)
    private static func flushRun(
        to buffer: UnsafeMutablePointer<UInt8>,
        offset: inout Int,
        count: Int,
        pixel: UInt16
    ) {
        var remaining = count
        // Little Endian 변환
        let lowByte = UInt8(pixel & 0xFF)
        let highByte = UInt8((pixel >> 8) & 0xFF)
        
        while remaining > 0 {
            // 최대 255개까지만 표현 가능
            let chunk = min(remaining, 255)
            
            // [Count(1)] [Pixel_Low(1)] [Pixel_High(1)] 직접 쓰기
            buffer[offset] = UInt8(chunk)
            buffer[offset + 1] = lowByte
            buffer[offset + 2] = highByte
            
            offset += 3
            remaining -= chunk
        }
    }
}
