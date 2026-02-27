//
//  MetalTileCompositor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2025/01/28.
//

import Foundation
import CoreGraphics
import CoreVideo
import Metal

/// GPU 기반 타일 합성기
final class MetalTileCompositor: CanvasTileCompositor {
    var frameSize: CGSize {
        didSet {
            if frameSize != oldValue {
                recreateTextures()
            }
        }
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var compositeTexture: MTLTexture?
    private(set) var canvasTexture: MTLTexture?
    private let tileTexturePool: TileTexturePool
    
    // ✨ 추가: CoreVideo와 Metal을 연결해주는 캐시
    private var textureCache: CVMetalTextureCache?
    private var outputPixelBufferPool: CVPixelBufferPool?
    
    // MARK: - Initialization

    init(frameSize: CGSize = .zero) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TileCompositorError.metalNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw TileCompositorError.commandQueueCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.tileTexturePool = TileTexturePool(device: device)
        self.frameSize = frameSize
        
        // ✨ Texture Cache 초기화
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache

        if frameSize != .zero {
            recreateTextures()
        }
    }

    deinit {
        invalidate()
    }

    // MARK: - CanvasTileCompositor

    func compositeToCanvas(_ frame: DecodedTileFrame) throws {
        if frameSize != frame.frameSize {
            frameSize = frame.frameSize
            recreateTextures()
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder(),
              let canvasTexture = self.canvasTexture else {
            throw TileCompositorError.commandBufferCreationFailed
        }

        if frame.isKeyFrame {
            clearTexture(canvasTexture, encoder: blitEncoder)
        }

        var usedTileTextures: [MTLTexture] = []
        for tile in frame.tiles {
            if let tileTexture = try blitTile(tile, to: canvasTexture, encoder: blitEncoder) {
                usedTileTextures.append(tileTexture)
            }
        }

        blitEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            for texture in usedTileTextures {
                self?.tileTexturePool.release(texture)
            }
        }

        commandBuffer.commit()
    }

    // MARK: - TileCompositor (legacy: CVPixelBuffer 출력)

    func composite(_ frame: DecodedTileFrame) throws -> CVPixelBuffer {
        if frameSize != frame.frameSize {
            frameSize = frame.frameSize
            recreateTextures()
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder(),
              let canvasTexture = self.canvasTexture else {
            throw TileCompositorError.commandBufferCreationFailed
        }

        if frame.isKeyFrame {
            clearTexture(canvasTexture, encoder: blitEncoder)
        }

        var usedTileTextures: [MTLTexture] = []
        for tile in frame.tiles {
            if let tileTexture = try blitTile(tile, to: canvasTexture, encoder: blitEncoder) {
                usedTileTextures.append(tileTexture)
            }
        }

        let outputBuffer = try acquireOutputBuffer()

        if let outputTexture = createTexture(from: outputBuffer) {
            blitEncoder.copy(
                from: canvasTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: canvasTexture.width, height: canvasTexture.height, depth: 1),
                to: outputTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }

        blitEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            for texture in usedTileTextures {
                self?.tileTexturePool.release(texture)
            }
        }

        commandBuffer.commit()

        return outputBuffer
    }

    func reset() {
        // 다음 composite 호출 시 키프레임 필요
    }

    func invalidate() {
        compositeTexture = nil
        outputPixelBufferPool = nil
        tileTexturePool.clear()
    }

    // MARK: - Private

    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTextureOut: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm, // CVPixelBuffer 포맷과 일치해야 함
            width,
            height,
            0,
            &cvTextureOut
        )
        
        guard status == kCVReturnSuccess, let cvTexture = cvTextureOut else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    private func recreateTextures() {
        guard frameSize.width > 0, frameSize.height > 0 else { return }
        
        // CVPixelBufferPool 생성
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(frameSize.width),
            kCVPixelBufferHeightKey: Int(frameSize.height),
            kCVPixelBufferMetalCompatibilityKey: true, // ✨ 필수 옵션
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary // ✨ 필수 (IOSurface 백킹)
        ]
        
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &outputPixelBufferPool)
        
        let canvasDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, // CVPixelBuffer와 동일하게 맞춤
            width: Int(frameSize.width),
            height: Int(frameSize.height),
            mipmapped: false
        )
        canvasDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        canvasDesc.storageMode = .private // GPU 전용이라 더 빠름
        
        self.canvasTexture = device.makeTexture(descriptor: canvasDesc)
    }

    private func clearTexture(_ texture: MTLTexture, encoder: MTLBlitCommandEncoder) {
        // 0으로 채우기 위한 임시 버퍼
        let bytesPerRow = texture.width * 4
        let size = bytesPerRow * texture.height

        if let clearBuffer = device.makeBuffer(length: size, options: .storageModeShared) {
            memset(clearBuffer.contents(), 0, size)

            encoder.copy(
                from: clearBuffer,
                sourceOffset: 0,
                sourceBytesPerRow: bytesPerRow,
                sourceBytesPerImage: size,
                sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                to: texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }

        // encoder.endEncoding()
    }

    @discardableResult
    private func blitTile(_ tile: DecodedTile, to texture: MTLTexture, encoder: any MTLBlitCommandEncoder) throws -> MTLTexture? {
        let tileX = Int(tile.rect.origin.x)
        let tileY = Int(tile.rect.origin.y)
        let tileWidth = Int(tile.rect.width)
        let tileHeight = Int(tile.rect.height)

        // 타일이 완전히 화면 밖이면 조용히 스킵
        guard tileX < texture.width, tileY < texture.height else {
            return nil
        }

        // 클리핑 계산
        let clippedWidth = min(tileWidth, texture.width - tileX)
        let clippedHeight = min(tileHeight, texture.height - tileY)

        guard clippedWidth > 0, clippedHeight > 0 else {
            return nil
        }

        // 타일 텍스처 획득 (원본 크기로)
        guard let tileTexture = tileTexturePool.acquire(width: tileWidth, height: tileHeight) else {
            throw TileCompositorError.textureCreationFailed
        }

        // 타일 데이터를 텍스처에 업로드
        tile.pixelData.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            tileTexture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: tileWidth, height: tileHeight, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: tileWidth * 4
            )
        }

        // 블리팅 (클리핑된 영역만)
        encoder.copy(
            from: tileTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: clippedWidth, height: clippedHeight, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: tileX, y: tileY, z: 0)
        )

        return tileTexture
    }

    private func acquireOutputBuffer() throws -> CVPixelBuffer {
        guard let pool = outputPixelBufferPool else {
            throw TileCompositorError.bufferPoolCreationFailed
        }

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)

        guard status == kCVReturnSuccess, let buffer else {
            throw TileCompositorError.bufferAcquisitionFailed
        }

        return buffer
    }

    private func copyTextureToPixelBuffer(_ texture: MTLTexture, to pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TileCompositorError.bufferAcquisitionFailed
        }

        texture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: texture.width, height: texture.height, depth: 1)
            ),
            mipmapLevel: 0
        )
    }
}
