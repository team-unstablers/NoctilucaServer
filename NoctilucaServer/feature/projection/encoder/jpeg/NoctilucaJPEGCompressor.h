//
//  NoctilucaJPEGCompressor.h
//  NoctilucaServer
//
//  libjpeg C API wrapper with setjmp/longjmp error handling.
//  Swift에서 직접 libjpeg을 호출하면 longjmp가 ARC 정리를 우회하므로,
//  이 C 헬퍼를 통해 에러 핸들링을 캡슐화한다.
//

#ifndef NOCTILUCA_JPEG_COMPRESSOR_H
#define NOCTILUCA_JPEG_COMPRESSOR_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 크로마 서브샘플링 모드
typedef enum {
    NJPEGSubsampling420 = 0,  ///< YCbCr 4:2:0 (luma 2x2, chroma 1x1)
    NJPEGSubsampling444 = 1,  ///< YCbCr 4:4:4 (모두 1x1)
} NJPEGSubsampling;

/// 압축 모드
typedef enum {
    /// 표준 JPEG quality (1-100) 기반 압축
    NJPEGCompressModeQuality = 0,
    /// 커스텀 양자화 테이블 기반 압축
    NJPEGCompressModeQuantTable = 1,
} NJPEGCompressMode;

/// 커스텀 양자화 테이블 (luminance + chrominance, 각 64개 값)
typedef struct {
    unsigned int luminance[64];   ///< 휘도 양자화 테이블 (natural/raster order)
    unsigned int chrominance[64]; ///< 색차 양자화 테이블 (natural/raster order)
    bool forceBaseline;           ///< true면 양자화 값을 baseline JPEG 범위(1-255)로 클램프
} NJPEGQuantTables;

/// BGRA 이미지를 JPEG으로 압축하는 파라미터
typedef struct {
    // 입력 이미지
    int width;
    int height;
    int bytesPerRow;              ///< stride (padding 포함)
    const uint8_t *inputBGRA;     ///< BGRA 픽셀 데이터 포인터

    // 압축 설정
    NJPEGSubsampling subsampling;
    NJPEGCompressMode mode;

    int quality;                       ///< mode == Quality일 때 사용 (1-100)
    const NJPEGQuantTables *quantTables; ///< mode == QuantTable일 때 사용

    // 출력 (성공 시 채워짐, 호출자가 njpeg_free로 해제)
    uint8_t *outBuffer;
    unsigned long outSize;
} NJPEGCompressParams;

/// BGRA 데이터를 JPEG로 압축한다.
///
/// @param params 압축 파라미터 (in/out). 성공 시 outBuffer와 outSize가 채워진다.
/// @param outErrorMsg 에러 메시지 버퍼 (최소 200바이트). 에러 시 null-terminated 문자열이 기록된다.
///                    NULL을 전달하면 에러 메시지를 기록하지 않는다.
/// @return 성공 시 0, 에러 시 -1
int njpeg_compress(NJPEGCompressParams *params, char *outErrorMsg);

/// njpeg_compress()가 할당한 outBuffer를 해제한다.
void njpeg_free(uint8_t *buffer);

#ifdef __cplusplus
}
#endif

#endif // NOCTILUCA_JPEG_COMPRESSOR_H
