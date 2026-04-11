//
//  noctiluca_vpx_decoder_shim.c
//  NoctilucaLibVPXDecoderShim
//

#include "include/noctiluca_vpx_decoder_shim.h"

#include <vpx/vpx_decoder.h>

int noctiluca_vpx_decoder_abi_version(void) {
    return VPX_DECODER_ABI_VERSION;
}
