//
//  NoctilucaJPEGCompressor.c
//  NoctilucaServer
//
//  libjpeg C API wrapper with setjmp/longjmp error handling.
//

#include "NoctilucaJPEGCompressor.h"

#include <stdio.h>
#include <stdlib.h>
#include <setjmp.h>
#include <string.h>

#include <libturbojpeg/jpeglib.h>
#include <libturbojpeg/jerror.h>

// MARK: - Error handler

/// setjmp 기반 확장 에러 매니저.
/// jpeg_error_mgr를 첫 번째 필드로 갖는 확장 구조체이므로,
/// libjpeg이 (jpeg_error_mgr *)로 캐스팅해 콜백을 호출하면
/// (njpeg_error_mgr *)로 역캐스팅하여 jmp_buf에 접근할 수 있다.
typedef struct {
    struct jpeg_error_mgr pub;
    jmp_buf setjmp_buffer;
    char error_msg[JMSG_LENGTH_MAX];
} njpeg_error_mgr;

static void njpeg_error_exit(j_common_ptr cinfo) {
    njpeg_error_mgr *myerr = (njpeg_error_mgr *)cinfo->err;
    (*cinfo->err->format_message)(cinfo, myerr->error_msg);
    longjmp(myerr->setjmp_buffer, 1);
}

// MARK: - Subsampling

/// 서브샘플링 팩터를 comp_info에 적용한다.
/// jpeg_set_defaults() 호출 후에 사용해야 한다.
static void njpeg_set_subsampling(struct jpeg_compress_struct *cinfo,
                                   NJPEGSubsampling subsampling) {
    if (cinfo->num_components < 3) return;

    switch (subsampling) {
    case NJPEGSubsampling444:
        cinfo->comp_info[0].h_samp_factor = 1;
        cinfo->comp_info[0].v_samp_factor = 1;
        cinfo->comp_info[1].h_samp_factor = 1;
        cinfo->comp_info[1].v_samp_factor = 1;
        cinfo->comp_info[2].h_samp_factor = 1;
        cinfo->comp_info[2].v_samp_factor = 1;
        break;
    case NJPEGSubsampling420:
    default:
        cinfo->comp_info[0].h_samp_factor = 2;
        cinfo->comp_info[0].v_samp_factor = 2;
        cinfo->comp_info[1].h_samp_factor = 1;
        cinfo->comp_info[1].v_samp_factor = 1;
        cinfo->comp_info[2].h_samp_factor = 1;
        cinfo->comp_info[2].v_samp_factor = 1;
        break;
    }
}

// MARK: - Compress

int njpeg_compress(NJPEGCompressParams *params, char *outErrorMsg) {
    struct jpeg_compress_struct cinfo;
    njpeg_error_mgr jerr;

    // 에러 매니저 설정
    cinfo.err = jpeg_std_error(&jerr.pub);
    jerr.pub.error_exit = njpeg_error_exit;
    memset(jerr.error_msg, 0, sizeof(jerr.error_msg));

    // setjmp 지점 — 에러 시 이곳으로 longjmp 복귀
    if (setjmp(jerr.setjmp_buffer)) {
        if (outErrorMsg) {
            strncpy(outErrorMsg, jerr.error_msg, JMSG_LENGTH_MAX - 1);
            outErrorMsg[JMSG_LENGTH_MAX - 1] = '\0';
        }
        jpeg_destroy_compress(&cinfo);
        return -1;
    }

    // jpeg_create_compress 매크로 대신 직접 호출
    jpeg_CreateCompress(&cinfo, JPEG_LIB_VERSION,
                        (size_t)sizeof(struct jpeg_compress_struct));

    // 메모리 출력 설정
    unsigned char *outBuf = NULL;
    unsigned long outSz = 0;
    jpeg_mem_dest(&cinfo, &outBuf, &outSz);

    // 이미지 파라미터
    cinfo.image_width = (JDIMENSION)params->width;
    cinfo.image_height = (JDIMENSION)params->height;
    cinfo.input_components = 4;
    cinfo.in_color_space = JCS_EXT_BGRA;

    // 기본값 설정 (in_color_space 설정 후 호출)
    jpeg_set_defaults(&cinfo);

    // 서브샘플링
    njpeg_set_subsampling(&cinfo, params->subsampling);

    // 압축 모드별 설정
    switch (params->mode) {
    case NJPEGCompressModeQuality:
        jpeg_set_quality(&cinfo, params->quality, TRUE);
        break;

    case NJPEGCompressModeQuantTable:
        if (params->quantTables) {
            // scale_factor=100 → 테이블 값 그대로 사용
            // (내부적으로 (table[i] * scale_factor + 50) / 100 연산)
            jpeg_add_quant_table(&cinfo, 0, params->quantTables->luminance,
                                 100, params->quantTables->forceBaseline);
            jpeg_add_quant_table(&cinfo, 1, params->quantTables->chrominance,
                                 100, params->quantTables->forceBaseline);
        } else {
            jpeg_set_quality(&cinfo, 90, TRUE);
        }
        break;
    }

    // 압축 시작
    jpeg_start_compress(&cinfo, TRUE);

    // 스캔라인 기록
    const uint8_t *rowPtr = params->inputBGRA;
    while (cinfo.next_scanline < cinfo.image_height) {
        JSAMPROW row = (JSAMPROW)rowPtr;
        jpeg_write_scanlines(&cinfo, &row, 1);
        rowPtr += params->bytesPerRow;
    }

    // 압축 완료
    jpeg_finish_compress(&cinfo);

    // 결과 설정
    params->outBuffer = outBuf;
    params->outSize = outSz;

    // 정리
    jpeg_destroy_compress(&cinfo);

    return 0;
}

void njpeg_free(uint8_t *buffer) {
    if (buffer) {
        free(buffer);
    }
}
