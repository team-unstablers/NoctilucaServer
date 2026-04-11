//
//  YUVColorMatrix.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/22/26.
//

import Foundation
import simd

import SiriusKitClient

/// YUV→RGB 변환에 필요한 컬러 매트릭스와 레인지 오프셋을 제공한다.
/// Qt의 QRhiVideoRenderer::buildColorMatrix/buildRangeOffset를 포팅.
enum YUVColorMatrix {

    // MARK: - Color Matrix (YUV → RGB)

    /// 주어진 VideoColorSpace에 대한 YUV→RGB 변환 행렬을 반환한다.
    /// column-major float4x4 (Metal simd_float4x4 호환).
    ///
    /// 행렬 구조 (yuv = vec4(Y, Cb, Cr, 1)):
    /// ```
    /// rgb = (colorMatrix * yuv).rgb
    /// ```
    static func matrix(for colorSpace: VideoColorSpace) -> simd_float4x4 {
        switch colorSpace {
        case .bt709:
            // ITU-R BT.709: Kr=0.2126, Kb=0.0722
            return simd_float4x4(
                SIMD4<Float>(1.0,      1.0,       1.0,     0.0),  // col 0 (Y)
                SIMD4<Float>(0.0,     -0.1873,    1.8556,  0.0),  // col 1 (Cb)
                SIMD4<Float>(1.5748,  -0.4681,    0.0,     0.0),  // col 2 (Cr)
                SIMD4<Float>(0.0,      0.0,       0.0,     1.0)   // col 3
            )

        case .bt601:
            // ITU-R BT.601: Kr=0.299, Kb=0.114
            return simd_float4x4(
                SIMD4<Float>(1.0,      1.0,       1.0,     0.0),
                SIMD4<Float>(0.0,     -0.344,     1.772,   0.0),
                SIMD4<Float>(1.402,   -0.714,     0.0,     0.0),
                SIMD4<Float>(0.0,      0.0,       0.0,     1.0)
            )

        case .bt2020PQ, .bt2020HLG:
            // ITU-R BT.2020: Kr=0.2627, Kb=0.0593
            return simd_float4x4(
                SIMD4<Float>(1.0,      1.0,       1.0,     0.0),
                SIMD4<Float>(0.0,     -0.1646,    1.8814,  0.0),
                SIMD4<Float>(1.4746,  -0.5714,    0.0,     0.0),
                SIMD4<Float>(0.0,      0.0,       0.0,     1.0)
            )

        case .sRGB:
            return matrix_identity_float4x4
        }
    }

    // MARK: - Range Offset

    /// 주어진 조건에 대한 레인지 오프셋 (yOffset, uvOffset, yScale, uvScale)을 반환한다.
    ///
    /// 셰이더에서의 사용:
    /// ```
    /// yuv.x = (yuv.x - rangeOffset.x) * rangeOffset.z  // Y
    /// yuv.y = (yuv.y - rangeOffset.y) * rangeOffset.w  // Cb
    /// yuv.z = (yuv.z - rangeOffset.y) * rangeOffset.w  // Cr
    /// ```
    static func rangeOffset(colorRange: CodecOptionValue, is10Bit: Bool) -> SIMD4<Float> {
        let isFull = colorRange == .kColorRangeFull

        if is10Bit {
            // Apple의 10-bit BiPlanar은 P010과 유사:
            // 상위 10비트가 유효하며, R16 UNORM으로 읽으면 0~65535 범위로 정규화됨.
            // 하지만 Apple은 상위 10비트를 왼쪽 시프트하여 저장하므로,
            // R16 UNORM 읽기 시 자동으로 [0, 1] 범위로 정규화된다.
            // → 8-bit와 동일한 offset/scale 사용 가능
            if isFull {
                return SIMD4(0.0, 0.5, 1.0, 1.0)
            } else {
                return SIMD4(16.0 / 255.0, 128.0 / 255.0, 255.0 / 219.0, 255.0 / 224.0)
            }
        }

        // 8-bit
        if isFull {
            return SIMD4(0.0, 0.5, 1.0, 1.0)
        } else {
            // Limited range: Y 16-235, UV 16-240
            return SIMD4(16.0 / 255.0, 128.0 / 255.0, 255.0 / 219.0, 255.0 / 224.0)
        }
    }

    // MARK: - Gamut Mapping Matrices

    /// Display P3 (D65) → sRGB 색역 변환 행렬.
    /// column-major, 각 컬럼이 float4로 패딩됨 (std140 호환).
    static let displayP3ToSRGB: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (
        SIMD4<Float>( 1.2249, -0.0420, -0.0196, 0.0),
        SIMD4<Float>(-0.2249,  1.0420, -0.0787, 0.0),
        SIMD4<Float>( 0.0000,  0.0000,  1.0983, 0.0)
    )

    /// Adobe RGB (1998, D65) → sRGB 색역 변환 행렬.
    static let adobeRGBToSRGB: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (
        SIMD4<Float>( 1.3982,  0.0000,  0.0000, 0.0),
        SIMD4<Float>(-0.3982,  1.0000, -0.0429, 0.0),
        SIMD4<Float>( 0.0000,  0.0000,  1.0429, 0.0)
    )

    // MARK: - FormatUniforms Builder

    /// Codec 정보로부터 FormatUniforms를 구성한다.
    static func buildFormatUniforms(colorSpace: VideoColorSpace, colorRange: CodecOptionValue, is10Bit: Bool) -> FormatUniforms {
        return FormatUniforms(
            colorMatrix: matrix(for: colorSpace),
            rangeOffset: rangeOffset(colorRange: colorRange, is10Bit: is10Bit)
        )
    }

    /// TonemapUniforms를 구성한다.
    static func buildTonemapUniforms(
        colorSpace: VideoColorSpace,
        maxLuminance: Float = 1000.0
    ) -> TonemapUniforms {
        var uniforms = TonemapUniforms()
        uniforms.transferFunction = colorSpace.transferFunctionIndex
        uniforms.toneMapEnabled = colorSpace.isHDR ? 1 : 0
        uniforms.maxLuminance = maxLuminance
        return uniforms
    }
}
