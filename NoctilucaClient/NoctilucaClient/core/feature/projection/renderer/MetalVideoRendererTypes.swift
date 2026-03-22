//
//  MetalVideoRendererTypes.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/22/26.
//

import Foundation
import Metal
import simd
import CoreVideo

import SiriusKitClient

// MARK: - Shader Uniform Structures

/// YUV→RGB 포맷 변환용 유니폼.
/// Metal 셰이더의 `FormatUniforms`와 메모리 레이아웃이 동일해야 한다.
struct FormatUniforms {
    /// YUV→RGB 변환 행렬 (column-major float4x4)
    var colorMatrix: simd_float4x4 = matrix_identity_float4x4
    /// (yOffset, uvOffset, yScale, uvScale)
    var rangeOffset: SIMD4<Float> = SIMD4(0, 0, 1, 1)
}

/// HDR 톤매핑용 유니폼.
/// Metal 셰이더의 `TonemapUniforms`와 메모리 레이아웃이 동일해야 한다.
struct TonemapUniforms {
    /// 전달 함수: 0=SDR, 1=PQ(ST.2084), 2=HLG
    var transferFunction: Int32 = 0
    /// 톤매핑 활성화 여부 (1=활성화)
    var toneMapEnabled: Int32 = 0
    /// 피크 밝기 (nits)
    var maxLuminance: Float = 1000.0
    /// 색역 매핑 활성화 여부 (1=활성화)
    var gamutMappingEnabled: Int32 = 0
    /// 색역 변환 행렬 (column-major, std140 패딩: 각 컬럼이 float4)
    var gamutMatrixCol0: SIMD4<Float> = SIMD4(1, 0, 0, 0)
    var gamutMatrixCol1: SIMD4<Float> = SIMD4(0, 1, 0, 0)
    var gamutMatrixCol2: SIMD4<Float> = SIMD4(0, 0, 1, 0)
}

/// CAS(Contrast Adaptive Sharpening) 유니폼.
struct CASUniforms {
    /// 텍셀 크기 (1.0/width, 1.0/height)
    var texelSize: SIMD2<Float> = .zero
    /// 선명도 (0.0~1.0)
    var sharpness: Float = 0.5
    var _pad: Float = 0
}

// MARK: - Video Color Space

/// 비디오 컬러 스페이스. YUV→RGB 변환 행렬 선택에 사용된다.
enum VideoColorSpace {
    case bt601
    case bt709
    case bt2020PQ
    case bt2020HLG
    case sRGB

    var isHDR: Bool {
        switch self {
        case .bt2020PQ, .bt2020HLG:
            return true
        default:
            return false
        }
    }

    /// 전달 함수 인덱스 (셰이더 TonemapUniforms.transferFunction에 대응)
    var transferFunctionIndex: Int32 {
        switch self {
        case .bt2020PQ: return 1
        case .bt2020HLG: return 2
        default: return 0
        }
    }
}

// MARK: - Metal Video Pixel Format

/// CVPixelBuffer의 BiPlanar YUV 포맷을 Metal 텍스처 포맷으로 매핑한다.
enum MetalVideoPixelFormat {
    /// 8-bit 4:2:0 BiPlanar (NV12)
    case biplanar420_8bit
    /// 10-bit 4:2:0 BiPlanar (P010)
    case biplanar420_10bit
    /// 8-bit 4:4:4 BiPlanar
    case biplanar444_8bit
    /// 10-bit 4:4:4 BiPlanar
    case biplanar444_10bit

    /// CVPixelBuffer의 OSType으로부터 생성
    init?(cvPixelFormat: OSType) {
        switch cvPixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            self = .biplanar420_8bit
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            self = .biplanar420_10bit
        case kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr8BiPlanarFullRange:
            self = .biplanar444_8bit
        case kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
            self = .biplanar444_10bit
        default:
            return nil
        }
    }

    /// Y 플레인의 Metal 텍스처 포맷
    var yPlaneFormat: MTLPixelFormat {
        switch self {
        case .biplanar420_8bit, .biplanar444_8bit:
            return .r8Unorm
        case .biplanar420_10bit, .biplanar444_10bit:
            return .r16Unorm
        }
    }

    /// UV(CbCr) 플레인의 Metal 텍스처 포맷
    var uvPlaneFormat: MTLPixelFormat {
        switch self {
        case .biplanar420_8bit, .biplanar444_8bit:
            return .rg8Unorm
        case .biplanar420_10bit, .biplanar444_10bit:
            return .rg16Unorm
        }
    }

    /// 10-bit 여부
    var is10Bit: Bool {
        switch self {
        case .biplanar420_10bit, .biplanar444_10bit:
            return true
        default:
            return false
        }
    }
}

// MARK: - Codec → VideoColorSpace 변환

extension VideoColorSpace {
    /// Codec 옵션으로부터 VideoColorSpace를 추론한다.
    init(from codec: SiriusKitClient.Codec) {
        if codec.isHDREnabled {
            // HDR 코덱은 기본 PQ 가정 (HLG는 CVPixelBuffer 어태치먼트로 판별)
            self = .bt2020PQ
        } else {
            self = .bt709
        }
    }

    /// CVPixelBuffer의 전달 함수 어태치먼트로 정밀 판별한다.
    /// Codec 기반 추론보다 우선한다.
    static func detect(from pixelBuffer: CVPixelBuffer, codec: SiriusKitClient.Codec) -> VideoColorSpace {
        guard codec.isHDREnabled else {
            return .bt709
        }

        return detectFromPixelBuffer(pixelBuffer)
    }

    /// CVPixelBuffer의 전달 함수 어태치먼트만으로 판별한다.
    /// 이미 HDR임을 알고 있을 때 per-frame 감지에 사용.
    static func detectFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> VideoColorSpace {
        if let transferFunction = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, nil) as? String {
            if transferFunction == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
                return .bt2020HLG
            }
            if transferFunction == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) {
                return .bt2020PQ
            }
        }

        return .bt2020PQ
    }
}
