//
//  noctiluca_vpx_shim.c
//  NoctilucaLibVPXShim
//

#include "include/noctiluca_vpx_shim.h"

#include <vpx/vpx_encoder.h>
#include <vpx/vp8cx.h>

int noctiluca_vpx_encoder_abi_version(void) {
    return VPX_ENCODER_ABI_VERSION;
}

int noctiluca_vpx_codec_control_int(void *ctx, int ctrlId, int value) {
    return vpx_codec_control_((vpx_codec_ctx_t *)ctx, ctrlId, value);
}

int noctiluca_vpx_codec_control_uint(void *ctx, int ctrlId, unsigned int value) {
    return vpx_codec_control_((vpx_codec_ctx_t *)ctx, ctrlId, value);
}
