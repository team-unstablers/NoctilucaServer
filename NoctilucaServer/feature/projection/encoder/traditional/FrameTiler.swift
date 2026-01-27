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
    
    // 캐싱 변수들
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
        
        // 픽셀 포맷 및 속성 가져오기
        let pixelFormat = CVPixelBufferGetPixelFormatType(image)
        let bytesPerPixel = self.bytesPerPixel(for: pixelFormat) ?? 4 // 기본값 4로 가정
        
        // 타일 버퍼 준비
        let tilesPerRow = paddedWidth / tileSize
        let tilesPerColumn = paddedHeight / tileSize
        let tileCount = tilesPerRow * tilesPerColumn
        
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any
        ] as CFDictionary
        
        let tileBuffers = acquireTileSet(
            tileSize: tileSize,
            paddedWidth: paddedWidth,
            paddedHeight: paddedHeight,
            pixelFormat: pixelFormat,
            tileCount: tileCount,
            attrs: attrs
        )
        
        if tileBuffers.isEmpty { return [] }
        
        // 소스 이미지 잠금 (읽기 전용)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        
        guard let srcBaseAddress = CVPixelBufferGetBaseAddress(image) else { return [] }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(image)
        let srcBaseRaw = UnsafeRawPointer(srcBaseAddress) // 불필요한 형변환 최소화
        
        // [최적화 1] 병렬 처리: 타일 개수만큼 병렬로 작업 수행
        DispatchQueue.concurrentPerform(iterations: tileCount) { index in
            if index >= tileBuffers.count { return }
            
            let tileBuffer = tileBuffers[index]
            
            // 현재 타일의 논리적 위치 계산 (이중 루프 대신 단일 인덱스 사용)
            let tileCol = index % tilesPerRow
            let tileRow = index / tilesPerRow
            let startX = tileCol * tileSize
            let startY = tileRow * tileSize
            
            CVPixelBufferLockBaseAddress(tileBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(tileBuffer, []) }
            
            guard let dstBaseAddress = CVPixelBufferGetBaseAddress(tileBuffer) else { return }
            let dstBytesPerRow = CVPixelBufferGetBytesPerRow(tileBuffer)
            let dstBaseRaw = UnsafeMutableRawPointer(dstBaseAddress)
            
            // 타일 내부 행(Row) 반복
            for row in 0..<tileSize {
                // 소스 이미지에서의 Y 좌표
                let currentY = startY + row
                // 이미지 범위를 벗어나면 마지막 줄을 계속 복사 (Clamping)
                let sourceY = min(height - 1, currentY)
                
                // 포인터 계산
                let srcRowPtr = srcBaseRaw.advanced(by: sourceY * srcBytesPerRow)
                let dstRowPtr = dstBaseRaw.advanced(by: row * dstBytesPerRow)
                
                // 복사할 유효 너비 계산
                let validWidth = (startX < width) ? min(width - startX, tileSize) : 0
                
                // 1. 유효한 이미지 데이터 복사 (memcpy)
                if validWidth > 0 {
                    let srcPixelPtr = srcRowPtr.advanced(by: startX * bytesPerPixel)
                    memcpy(dstRowPtr, srcPixelPtr, validWidth * bytesPerPixel)
                }
                
                // 2. 패딩 처리 (이미지 오른쪽 끝부분)
                if validWidth < tileSize {
                    // 마지막 유효 픽셀의 위치 (유효 데이터가 없으면 0번째 픽셀)
                    let lastPixelIndex = max(0, min(width - 1, startX + validWidth - 1))
                    // 원본에서의 마지막 픽셀 포인터 (소스에서 가져옴)
                    let lastPixelPtr = srcRowPtr.advanced(by: lastPixelIndex * bytesPerPixel)
                    
                    // 채워야 할 시작 지점
                    let fillStartPtr = dstRowPtr.advanced(by: validWidth * bytesPerPixel)
                    let fillCount = tileSize - validWidth
                    
                    // [최적화 2] 4바이트(32bit) 픽셀인 경우 memset_pattern4 사용
                    // 기존: for 루프 내 memcpy (CPU 과부하 원인) -> 변경: 시스템 최적화 함수
                    if bytesPerPixel == 4 {
                        memset_pattern4(fillStartPtr, lastPixelPtr, fillCount * 4)
                    } else {
                        // 4바이트가 아닌 경우 (예외적) - 루프 대신 패턴 복사 시도
                        // 단순히 루프를 돌리더라도 UnsafeRawPointer 레벨에서 처리하여 Iterator 오버헤드 감소
                        var currentFillPtr = fillStartPtr
                        for _ in 0..<fillCount {
                            memcpy(currentFillPtr, lastPixelPtr, bytesPerPixel)
                            currentFillPtr += bytesPerPixel
                        }
                    }
                }
            }
        }
        
        // 메타데이터 전파 (첫 프레임에서만)
        if shouldPropagateAttachments {
            // 병렬 처리 후 메인 스레드나 호출 스레드에서 수행해도 무방하지만,
            // 안전을 위해 타일 배열 순회
            for tile in tileBuffers {
                CVBufferPropagateAttachments(image, tile)
            }
            shouldPropagateAttachments = false
        }
        
        return tileBuffers
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
            // 다른 포맷이 필요하다면 여기에 추가 (예: YpCbCr 등은 평면이 달라 로직 변경 필요)
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
