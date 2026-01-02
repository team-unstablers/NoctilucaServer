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
    private var cachedTileSets: [[CVPixelBuffer]] = []
    private var cachedTileSize: Int = 0
    private var cachedPaddedWidth: Int = 0
    private var cachedPaddedHeight: Int = 0
    private var cachedPixelFormat: OSType = 0
    private var cachedTileCount: Int = 0
    private var shouldPropagateAttachments: Bool = true
    private var tileSetIndex: Int = 0
    
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

        let tilesPerRow = max(1, paddedWidth / tileSize)
        let tilesPerColumn = max(1, paddedHeight / tileSize)
        let tileCount = tilesPerRow * tilesPerColumn
        let tileBuffers = acquireTileSet(
            tileSize: tileSize,
            paddedWidth: paddedWidth,
            paddedHeight: paddedHeight,
            pixelFormat: pixelFormat,
            tileCount: tileCount,
            attrs: attrs
        )
        if tileBuffers.isEmpty {
            return []
        }
        
        let bytesPerPixel = bytesPerPixel(for: pixelFormat)!
        
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(image) else { return [] }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(image)
        let srcBase = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var tileIndex = 0
        for y in stride(from: 0, to: paddedHeight, by: tileSize) {
            for x in stride(from: 0, to: paddedWidth, by: tileSize) {
                if tileIndex >= tileBuffers.count { break }
                let pixelBuffer = tileBuffers[tileIndex]
                tileIndex += 1
                
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
        
        if shouldPropagateAttachments {
            for tile in tiles {
                CVBufferPropagateAttachments(image, tile)
            }
            
            shouldPropagateAttachments = false
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

    func acquireTileSet(
        tileSize: Int,
        paddedWidth: Int,
        paddedHeight: Int,
        pixelFormat: OSType,
        tileCount: Int,
        attrs: CFDictionary
    ) -> [CVPixelBuffer] {
        let shouldRebuild = cachedTileSize != tileSize ||
        cachedPaddedWidth != paddedWidth ||
        cachedPaddedHeight != paddedHeight ||
        cachedPixelFormat != pixelFormat ||
        cachedTileCount != tileCount ||
        cachedTileSets.count != 2 ||
        cachedTileSets.contains(where: { $0.count != tileCount })
        
        if shouldRebuild {
            var newSets: [[CVPixelBuffer]] = []
            newSets.reserveCapacity(2)
            
            for _ in 0..<2 {
                var tiles: [CVPixelBuffer] = []
                tiles.reserveCapacity(tileCount)
                
                for _ in 0..<tileCount {
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
                        return []
                    }
                    
                    tiles.append(pixelBuffer)
                }
                
                newSets.append(tiles)
            }
            
            cachedTileSets = newSets
            cachedTileSize = tileSize
            cachedPaddedWidth = paddedWidth
            cachedPaddedHeight = paddedHeight
            cachedPixelFormat = pixelFormat
            cachedTileCount = tileCount
            tileSetIndex = 0
            shouldPropagateAttachments = true
        }
        
        let index = tileSetIndex
        tileSetIndex = (tileSetIndex + 1) % 2
        return cachedTileSets[index]
    }
}
