//
//  TileCompositor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2025/01/28.
//

import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo

/// 디코딩된 단일 타일
struct DecodedTile {
    /// 프레임 내 타일 위치 및 크기
    let rect: CGRect

    /// 디코딩된 픽셀 데이터 (BGRA, row-major)
    /// - 크기: width × height × 4 bytes
    let pixelData: Data
}

/// 타일 프레임 (디코더 출력)
struct DecodedTileFrame {
    /// 이 프레임에 포함된 타일들
    let tiles: [DecodedTile]

    /// Presentation Time Stamp
    let pts: CMTime

    /// 키프레임 여부 (true면 전체 프레임 재구성, false면 이전 프레임에 덧씌움)
    let isKeyFrame: Bool

    /// 전체 프레임 크기
    let frameSize: CGSize

    /// 디코드 소요 시간 (밀리초)
    let decodeTimeMs: Double
}

/// 타일 기반 디코더 델리게이트
protocol TiledVideoDecoderDelegate: AnyObject {
    func tiledVideoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedTileFrame)
}

/// 타일 합성기 프로토콜
protocol TileCompositor: AnyObject {
    /// 프레임 크기 (변경 시 내부 버퍼 재생성)
    var frameSize: CGSize { get set }

    /// 타일들을 합성하여 CVPixelBuffer 생성
    /// - Parameter frame: 디코딩된 타일 프레임
    /// - Returns: 합성된 전체 프레임
    func composite(_ frame: DecodedTileFrame) throws -> CVPixelBuffer

    /// 내부 상태 초기화 (키프레임 대기 상태로)
    func reset()

    /// 리소스 해제
    func invalidate()
}
