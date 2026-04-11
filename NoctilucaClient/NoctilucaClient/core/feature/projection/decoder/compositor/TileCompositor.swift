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
import Metal

/// 디코딩된 단일 타일
struct DecodedTile: Sendable {
    /// 프레임 내 타일 위치 및 크기
    let rect: CGRect

    /// 디코딩된 픽셀 데이터 (BGRA, row-major)
    /// - 크기: width × height × 4 bytes
    let pixelData: Data
}

/// 타일 프레임 (디코더 출력)
struct DecodedTileFrame: Sendable {
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
protocol TiledVideoDecoderDelegate: AnyObject, Sendable {
    func tiledVideoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedTileFrame)
}

/// 타일 합성기 프로토콜
protocol TileCompositor: AnyObject, Sendable {
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

/// GPU 캔버스에 직접 접근할 수 있는 타일 합성기 프로토콜.
///
/// MetalProjectionView가 캔버스 텍스처를 직접 렌더링할 수 있도록
/// CVPixelBuffer 복사 없이 캔버스만 업데이트하는 경로를 제공한다.
protocol CanvasTileCompositor: TileCompositor {
    /// GPU 캔버스 텍스처 (read-only). 타일이 블리팅된 최종 합성 결과.
    var canvasTexture: MTLTexture? { get }

    /// Metal 디바이스
    var device: MTLDevice { get }

    /// 타일을 캔버스에만 합성한다 (CVPixelBuffer 복사 없음).
    /// - Parameter frame: 디코딩된 타일 프레임
    func compositeToCanvas(_ frame: DecodedTileFrame) throws
}
