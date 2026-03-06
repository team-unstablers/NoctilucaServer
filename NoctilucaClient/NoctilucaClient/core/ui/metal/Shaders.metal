#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 textureCoordinate [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
};

// 화면 크기 및 커서 정보
struct CursorUniforms {
    float2 cursorPosition; // Pixels (viewport space, top-left origin)
    float2 cursorSize;     // Pixels
    float2 hotspot;        // Pixels (offset from top-left)
    float2 viewportSize;   // Viewport Pixels (Width, Height)
};

vertex VertexOut cursor_vertex(
    const device VertexIn* vertex_array [[ buffer(0) ]],
    constant CursorUniforms& uniforms [[ buffer(1) ]],
    unsigned int vid [[ vertex_id ]]
) {
    VertexIn in = vertex_array[vid];
    VertexOut out;

    // 1. 커서의 픽셀 좌표 계산 (Top-Left 기준)
    // cursorPosition은 (0~1)이므로 뷰포트 크기를 곱해 픽셀 좌표로 변환
    float2 pixelPos = uniforms.cursorPosition;
    
    // 2. 핫스팟 보정 및 버텍스 오프셋 적용
    // 버텍스(Quad)는 0.0 ~ 1.0 사이의 값을 가짐 (Quad 정의에 따라 다름)
    // 여기서는 Quad를 (0,0)~(1,1) 크기로 정의했다고 가정하고 cursorSize를 곱함
    float2 vertexOffset = in.position * uniforms.cursorSize;
    
    float2 finalPixelPos = pixelPos - uniforms.hotspot + vertexOffset;

    // 3. Screen Space (Pixel) -> NDC Space (-1 ~ 1) 변환
    // Metal NDC: X(-1~1), Y(-1~1). Center(0,0).
    // UI 좌표계: Top-Left(0,0), Bottom-Right(W,H)
    
    float2 ndcPos;
    ndcPos.x = (finalPixelPos.x / uniforms.viewportSize.x) * 2.0 - 1.0;
    // Y축: UI는 아래로 갈수록 양수, Metal은 위로 갈수록 양수 -> 뒤집어야 함
    ndcPos.y = ((uniforms.viewportSize.y - finalPixelPos.y) / uniforms.viewportSize.y) * 2.0 - 1.0;

    out.position = float4(ndcPos, 0.0, 1.0);
    out.textureCoordinate = in.textureCoordinate;

    return out;
}

fragment float4 cursor_fragment(
    VertexOut interpolated [[stage_in]],
    texture2d<float>  tex [[ texture(0) ]],
    sampler           samp [[ sampler(0) ]]
) {
    // 텍스처 샘플링 (투명도 포함)
    // 텍스처가 없거나 로드되지 않았을 경우를 대비해 투명 처리 로직이 필요할 수도 있지만,
    // Swift 코드에서 텍스처가 없으면 draw call을 안 하는 게 더 효율적임.
    return tex.sample(samp, interpolated.textureCoordinate);
}

// MARK: - Projection (Canvas → Screen)

// Fullscreen quad vertex shader.
// vertex_id 0~3으로 삼각형 스트립 2개를 만들어 화면 전체를 덮는다.
vertex VertexOut projection_vertex(unsigned int vid [[ vertex_id ]]) {
    // triangle strip: (0,0) → (1,0) → (0,1) → (1,1)
    float2 uv = float2(vid & 1, (vid >> 1) & 1);

    VertexOut out;
    // NDC: x [-1, 1], y [-1, 1]
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    // UV: y를 뒤집어야 함 (Metal 텍스처 원점 = top-left, NDC y축 = bottom-up)
    out.textureCoordinate = float2(uv.x, 1.0 - uv.y);
    return out;
}

fragment float4 projection_fragment(
    VertexOut interpolated [[stage_in]],
    texture2d<float> tex [[ texture(0) ]],
    sampler           samp [[ sampler(0) ]]
) {
    return tex.sample(samp, interpolated.textureCoordinate);
}
