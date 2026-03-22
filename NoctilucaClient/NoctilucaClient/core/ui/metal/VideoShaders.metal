//
//  VideoShaders.metal
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/22/26.
//
//  Qt의 QRhiVideoRenderer 셰이더를 MSL로 포팅.
//  YUV→RGB 포맷 변환, HDR 톤매핑, CAS 후처리를 처리한다.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Structures

struct VideoVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct FormatUniforms {
    float4x4 colorMatrix;  // YUV→RGB 변환 행렬 (column-major)
    float4 rangeOffset;    // (yOffset, uvOffset, yScale, uvScale)
};

struct TonemapUniforms {
    int transferFunction;      // 0=SDR, 1=PQ, 2=HLG
    int toneMapEnabled;        // 1=활성화
    float maxLuminance;        // 피크 밝기 (nits)
    int gamutMappingEnabled;   // 1=활성화
    float4 gamutMatrixCol0;    // 색역 변환 행렬 column 0
    float4 gamutMatrixCol1;    // column 1
    float4 gamutMatrixCol2;    // column 2
};

struct CASUniforms {
    float2 texelSize;    // 1.0/width, 1.0/height
    float sharpness;     // 0.0~1.0
    float _pad;
};

// MARK: - Vertex Shader

/// Fullscreen triangle (vertex buffer 불필요).
/// vertex_id 0~2로 화면 전체를 덮는 삼각형 1개를 생성한다.
vertex VideoVertexOut video_format_vertex(uint vid [[vertex_id]]) {
    // 0 → (0,0), 1 → (2,0), 2 → (0,2)
    float2 pos = float2(float((vid << 1) & 2), float(vid & 2));

    VideoVertexOut out;
    // Metal 텍스처 원점 = top-left, NDC y축 = bottom-up
    out.texCoord = float2(pos.x, 1.0 - pos.y);
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - Format Fragment Shaders

/// BiPlanar YUV→RGB 변환 (NV12/P010/YUV444 공용).
///
/// Apple의 CVPixelBuffer BiPlanar 포맷은 모두 동일한 구조:
/// - plane 0: Y (R8 또는 R16)
/// - plane 1: CbCr (RG8 또는 RG16)
/// 텍스처 포맷과 rangeOffset만 다르므로 하나의 셰이더로 모든 BiPlanar YUV를 처리한다.
fragment float4 format_biplanar(
    VideoVertexOut in [[stage_in]],
    texture2d<float> texY  [[texture(0)]],
    texture2d<float> texUV [[texture(1)]],
    constant FormatUniforms& uniforms [[buffer(0)]],
    sampler s [[sampler(0)]]
) {
    float y  = texY.sample(s, in.texCoord).r;
    float2 uv = texUV.sample(s, in.texCoord).rg;

    float4 yuv = float4(y, uv.x, uv.y, 1.0);

    // Range normalization
    yuv.x = (yuv.x - uniforms.rangeOffset.x) * uniforms.rangeOffset.z;
    yuv.y = (yuv.y - uniforms.rangeOffset.y) * uniforms.rangeOffset.w;
    yuv.z = (yuv.z - uniforms.rangeOffset.y) * uniforms.rangeOffset.w;

    float3 rgb = (uniforms.colorMatrix * yuv).rgb;
    return float4(clamp(rgb, 0.0, 1.0), 1.0);
}

/// BiPlanar YUV→RGB 변환 (HDR 경로용, 출력을 클램핑하지 않음).
/// RGBA16F 중간 텍스처로 출력할 때 사용한다.
fragment float4 format_biplanar_hdr(
    VideoVertexOut in [[stage_in]],
    texture2d<float> texY  [[texture(0)]],
    texture2d<float> texUV [[texture(1)]],
    constant FormatUniforms& uniforms [[buffer(0)]],
    sampler s [[sampler(0)]]
) {
    float y  = texY.sample(s, in.texCoord).r;
    float2 uv = texUV.sample(s, in.texCoord).rg;

    float4 yuv = float4(y, uv.x, uv.y, 1.0);
    yuv.x = (yuv.x - uniforms.rangeOffset.x) * uniforms.rangeOffset.z;
    yuv.y = (yuv.y - uniforms.rangeOffset.y) * uniforms.rangeOffset.w;
    yuv.z = (yuv.z - uniforms.rangeOffset.y) * uniforms.rangeOffset.w;

    float3 rgb = (uniforms.colorMatrix * yuv).rgb;
    // HDR: 클램핑하지 않음 — 중간 텍스처(RGBA16F)에 전체 범위를 보존
    return float4(rgb, 1.0);
}

// MARK: - Tonemap Shader

/// PQ (ST.2084) inverse EOTF: 정규화 [0,1] → 선형 휘도 [0, 10000] nits
static float3 pqInverseEOTF(float3 pq) {
    constexpr float m1 = 0.1593017578125;
    constexpr float m2 = 78.84375;
    constexpr float c1 = 0.8359375;
    constexpr float c2 = 18.8515625;
    constexpr float c3 = 18.6875;

    float3 p = pow(max(pq, float3(0.0)), float3(1.0 / m2));
    float3 num = max(p - c1, float3(0.0));
    float3 den = c2 - c3 * p;
    return pow(num / max(den, float3(1e-6)), float3(1.0 / m1)) * 10000.0;
}

/// HLG inverse OETF: 정규화 [0,1] → scene-linear
static float3 hlgInverseOETF(float3 hlg) {
    constexpr float a = 0.17883277;
    constexpr float b = 0.28466892;   // 1.0 - 4.0 * a
    constexpr float c_val = 0.55991073;   // 0.5 - a * ln(4.0 * a)

    float3 result;
    for (int i = 0; i < 3; i++) {
        float v = hlg[i];
        if (v <= 0.5) {
            result[i] = (v * v) / 3.0;
        } else {
            result[i] = (exp((v - c_val) / a) + b) / 12.0;
        }
    }
    return result;
}

/// Reinhard 톤 매핑: linear nits → [0, 1] SDR
static float3 reinhardToneMap(float3 linearNits, float maxLum) {
    float3 normalized = linearNits / maxLum;
    return normalized / (1.0 + normalized);
}

/// linear → sRGB OETF
static float3 linearToSRGB(float3 linear) {
    float3 lo = linear * 12.92;
    float3 hi = 1.055 * pow(max(linear, float3(0.0)), float3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(float3(0.0031308), linear));
}

/// sRGB → linear (inverse EOTF)
static float3 sRGBToLinear(float3 srgb) {
    float3 lo = srgb / 12.92;
    float3 hi = pow(max((srgb + 0.055) / 1.055, float3(0.0)), float3(2.4));
    return mix(lo, hi, step(float3(0.04045), srgb));
}

/// HDR→SDR 톤매핑 + 색역 매핑 프래그먼트 셰이더.
fragment float4 tonemap_fragment(
    VideoVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant TonemapUniforms& uniforms [[buffer(0)]],
    sampler s [[sampler(0)]]
) {
    float3 rgb = tex.sample(s, in.texCoord).rgb;

    if (uniforms.transferFunction == 1) {
        // PQ (ST.2084)
        float3 linearNits = pqInverseEOTF(rgb);
        rgb = reinhardToneMap(linearNits, uniforms.maxLuminance);

        if (uniforms.gamutMappingEnabled != 0) {
            float3x3 gamutMatrix = float3x3(
                uniforms.gamutMatrixCol0.xyz,
                uniforms.gamutMatrixCol1.xyz,
                uniforms.gamutMatrixCol2.xyz
            );
            rgb = gamutMatrix * rgb;
        }

        rgb = linearToSRGB(clamp(rgb, 0.0, 1.0));
    } else if (uniforms.transferFunction == 2) {
        // HLG
        float3 sceneLinear = hlgInverseOETF(rgb);
        float3 displayLinear = pow(sceneLinear, float3(1.2)) * 1000.0;
        rgb = reinhardToneMap(displayLinear, uniforms.maxLuminance);

        if (uniforms.gamutMappingEnabled != 0) {
            float3x3 gamutMatrix = float3x3(
                uniforms.gamutMatrixCol0.xyz,
                uniforms.gamutMatrixCol1.xyz,
                uniforms.gamutMatrixCol2.xyz
            );
            rgb = gamutMatrix * rgb;
        }

        rgb = linearToSRGB(clamp(rgb, 0.0, 1.0));
    } else if (uniforms.gamutMappingEnabled != 0) {
        // SDR with wide gamut
        float3 linear = sRGBToLinear(rgb);
        float3x3 gamutMatrix = float3x3(
            uniforms.gamutMatrixCol0.xyz,
            uniforms.gamutMatrixCol1.xyz,
            uniforms.gamutMatrixCol2.xyz
        );
        linear = gamutMatrix * linear;
        rgb = linearToSRGB(clamp(linear, 0.0, 1.0));
    }

    return float4(rgb, 1.0);
}

// MARK: - CAS (Contrast Adaptive Sharpening) Shader

/// AMD FidelityFX CAS 5-tap 알고리즘.
fragment float4 cas_fragment(
    VideoVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    constant CASUniforms& uniforms [[buffer(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in.texCoord;

    // 5-tap cross pattern sampling
    float3 b = tex.sample(s, uv + float2( 0.0,                -uniforms.texelSize.y)).rgb; // N
    float3 d = tex.sample(s, uv + float2(-uniforms.texelSize.x, 0.0)).rgb;                  // W
    float3 e = tex.sample(s, uv).rgb;                                                        // Center
    float3 f = tex.sample(s, uv + float2( uniforms.texelSize.x, 0.0)).rgb;                  // E
    float3 h = tex.sample(s, uv + float2( 0.0,                 uniforms.texelSize.y)).rgb; // S

    // Local min/max
    float3 mnRGB = min(min(min(b, d), min(f, h)), e);
    float3 mxRGB = max(max(max(b, d), max(f, h)), e);

    // Contrast-adaptive weight
    float3 rcpM = 1.0 / max(mxRGB, float3(1.0 / 65536.0));
    float3 ampRGB = clamp(
        min(mnRGB * rcpM, (2.0 - mxRGB) * rcpM),
        float3(0.0), float3(1.0)
    );
    ampRGB = sqrt(ampRGB);

    // peak: -0.125 (sharpness=0) ~ -0.2 (sharpness=1)
    float peak = -1.0 / mix(8.0, 5.0, clamp(uniforms.sharpness, 0.0, 1.0));
    float3 w = ampRGB * peak;

    // Weighted filter
    float3 result = (b * w + d * w + f * w + h * w + e) / (4.0 * w + 1.0);

    return float4(clamp(result, 0.0, 1.0), 1.0);
}
