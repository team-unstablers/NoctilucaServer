//
//  FrameTiler.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation

import CoreImage
import CoreGraphics
import Metal

class FrameTiler {
    private(set) var tileSize: Int
    private let ciContext: CIContext
    
    init(tileSize: Int) {
        self.tileSize = max(1, tileSize)
        
        if let device = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: device)
        } else {
            self.ciContext = CIContext()
        }
    }
    
    /// 이미지를 타일로 분할합니다.
    func tile(_ image: CVImageBuffer) -> [CVImageBuffer] {
        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)
        guard width > 0, height > 0 else { return [] }
        
        let tileSize = max(1, self.tileSize)
        let paddedWidth = ((width + tileSize - 1) / tileSize) * tileSize
        let paddedHeight = ((height + tileSize - 1) / tileSize) * tileSize
        
        var tiles: [CVImageBuffer] = []
        tiles.reserveCapacity((paddedWidth / tileSize) * (paddedHeight / tileSize))
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(image)
        let colorSpace = CVImageBufferGetColorSpace(image)?.takeUnretainedValue() ?? CGColorSpaceCreateDeviceRGB()
        
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any
        ] as CFDictionary

        if let bytesPerPixel = bytesPerPixel(for: pixelFormat) {
            CVPixelBufferLockBaseAddress(image, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(image) else { return [] }
            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(image)
            let srcBase = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            for y in stride(from: 0, to: paddedHeight, by: tileSize) {
                for x in stride(from: 0, to: paddedWidth, by: tileSize) {
                    var pixelBuffer: CVPixelBuffer?
                    let status = CVPixelBufferCreate(
                        kCFAllocatorDefault,
                        tileSize,
                        tileSize,
                        pixelFormat,
                        attrs,
                        &pixelBuffer
                    )
                    
                    guard status == kCVReturnSuccess, let pixelBuffer else {
                        continue
                    }
                    
                    CVBufferPropagateAttachments(image, pixelBuffer)
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    
                    if let dstBase = CVPixelBufferGetBaseAddress(pixelBuffer) {
                        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                        let dst = dstBase.assumingMemoryBound(to: UInt8.self)
                        
                        for row in 0..<tileSize {
                            let sourceY = min(height - 1, y + row)
                            let srcRow = srcBase + (sourceY * srcBytesPerRow)
                            let dstRow = dst + (row * dstBytesPerRow)
                            
                            let copyWidth = x < width ? min(width - x, tileSize) : 0
                            if copyWidth > 0 {
                                let srcStart = srcRow + (x * bytesPerPixel)
                                memcpy(dstRow, srcStart, copyWidth * bytesPerPixel)
                            }
                            
                            let lastPixelX = max(0, min(width - 1, x + copyWidth - 1))
                            let lastPixel = srcRow + (lastPixelX * bytesPerPixel)
                            if copyWidth < tileSize {
                                var dstPixel = dstRow + (copyWidth * bytesPerPixel)
                                for _ in copyWidth..<tileSize {
                                    memcpy(dstPixel, lastPixel, bytesPerPixel)
                                    dstPixel += bytesPerPixel
                                }
                            }
                        }
                    }
                    
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                    tiles.append(pixelBuffer)
                }
            }
            
            return tiles
        }

        let ciImage = CIImage(cvImageBuffer: image)
        let extent = ciImage.extent.integral
        let paddedExtent = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: CGFloat(paddedWidth),
            height: CGFloat(paddedHeight)
        )
        
        let paddedImage: CIImage
        if paddedWidth == Int(extent.width) && paddedHeight == Int(extent.height) {
            paddedImage = ciImage
        } else {
            paddedImage = ciImage.clampedToExtent().cropped(to: paddedExtent)
        }
        
        for y in stride(from: 0, to: paddedHeight, by: tileSize) {
            for x in stride(from: 0, to: paddedWidth, by: tileSize) {
                let tileRect = CGRect(
                    x: extent.origin.x + CGFloat(x),
                    y: extent.origin.y + CGFloat(y),
                    width: CGFloat(tileSize),
                    height: CGFloat(tileSize)
                )
                
                var pixelBuffer: CVPixelBuffer?
                let status = CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    tileSize,
                    tileSize,
                    pixelFormat,
                    attrs,
                    &pixelBuffer
                )
                
                guard status == kCVReturnSuccess, let pixelBuffer else {
                    continue
                }
                
                CVBufferPropagateAttachments(image, pixelBuffer)
                let tileImage = paddedImage
                    .cropped(to: tileRect)
                    .transformed(by: CGAffineTransform(translationX: -tileRect.origin.x, y: -tileRect.origin.y))
                let destinationBounds = CGRect(x: 0, y: 0, width: CGFloat(tileSize), height: CGFloat(tileSize))
                ciContext.render(tileImage, to: pixelBuffer, bounds: destinationBounds, colorSpace: colorSpace)
                tiles.append(pixelBuffer)
            }
        }
        
        return tiles
    }
}

private extension FrameTiler {
    func bytesPerPixel(for pixelFormat: OSType) -> Int? {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_32RGBA,
             kCVPixelFormatType_32ARGB,
             kCVPixelFormatType_32ABGR:
            return 4
        default:
            return nil
        }
    }
}
