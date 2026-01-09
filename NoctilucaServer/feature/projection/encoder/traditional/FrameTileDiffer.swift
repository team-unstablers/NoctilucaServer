//
//  FrameTileDiffer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation

import CoreImage
import CoreGraphics

/// Tile diff를 행해서 dirty rect를 검출합니다
class FrameTileDiffer {
    // 타일 목록
    private(set) var previousTiles: [CVImageBuffer] = []
    
    /// 타일들을 피드하며, 기존 타일과 다른 타일의 인덱스 셋을 반환합니다
    func feed(_ tiles: [CVImageBuffer]) -> Set<Int> {
        if previousTiles.count != tiles.count {
            // 타일 개수가 변경된 경우, 모두 다르다고 간주합니다
            previousTiles = tiles
            return Set(0..<tiles.count)
        }
        
        var dirtyTileIndices: Set<Int> = []
        
        /// memcmp 기반으로 내용물을 비교한다. memcmp 내부에서 SIMD를 통한 비교를 행해줄 것이라고 믿어보자..
        for (index, tile) in tiles.enumerated() {
            let previousTile = previousTiles[index]
            
            let width = CVPixelBufferGetWidth(tile)
            let height = CVPixelBufferGetHeight(tile)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(tile)
            let pixelFormat = CVPixelBufferGetPixelFormatType(tile)
            
            let prevWidth = CVPixelBufferGetWidth(previousTile)
            let prevHeight = CVPixelBufferGetHeight(previousTile)
            let prevBytesPerRow = CVPixelBufferGetBytesPerRow(previousTile)
            let prevPixelFormat = CVPixelBufferGetPixelFormatType(previousTile)
            
            guard width == prevWidth,
                  height == prevHeight,
                  bytesPerRow == prevBytesPerRow,
                  pixelFormat == prevPixelFormat
            else {
                // 크기나 바이트 퍼 로우가 다른 경우, 다르다고 간주
                dirtyTileIndices.insert(index)
                continue
            }
            
            CVPixelBufferLockBaseAddress(tile, .readOnly)
            CVPixelBufferLockBaseAddress(previousTile, .readOnly)
            
            if let baseAddress1 = CVPixelBufferGetBaseAddress(tile),
               let baseAddress2 = CVPixelBufferGetBaseAddress(previousTile) {
                let size = bytesPerRow * height
                if memcmp(baseAddress1, baseAddress2, size) != 0 {
                    dirtyTileIndices.insert(index)
                }
            } else {
                // 베이스 주소를 얻지 못한 경우, 다르다고 간주
                dirtyTileIndices.insert(index)
            }
            
            CVPixelBufferUnlockBaseAddress(tile, .readOnly)
            CVPixelBufferUnlockBaseAddress(previousTile, .readOnly)
        }
        
        // 현재 타일을 이전 타일로 갱신
        previousTiles = tiles
        
        return dirtyTileIndices
    }
    
    func reset() {
        previousTiles.removeAll()
    }
}
