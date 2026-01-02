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
        let ciImage = CIImage(cvImageBuffer: image)
        let extent = ciImage.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return [] }
        
        let tileSize = max(1, self.tileSize)
        let paddedWidth = ((width + tileSize - 1) / tileSize) * tileSize
        let paddedHeight = ((height + tileSize - 1) / tileSize) * tileSize
        let paddedExtent = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: CGFloat(paddedWidth),
            height: CGFloat(paddedHeight)
        )
        
        let paddedImage: CIImage
        if paddedWidth == width && paddedHeight == height {
            paddedImage = ciImage
        } else {
            paddedImage = ciImage.clampedToExtent().cropped(to: paddedExtent)
        }
        
        var tiles: [CVImageBuffer] = []
        tiles.reserveCapacity((paddedWidth / tileSize) * (paddedHeight / tileSize))
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(image)
        let colorSpace = CVImageBufferGetColorSpace(image)
        
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any
        ] as CFDictionary
        
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
                ciContext.render(paddedImage, to: pixelBuffer, bounds: tileRect, colorSpace: colorSpace as! CGColorSpace)
                tiles.append(pixelBuffer)
            }
        }
        
        return tiles
    }
}
