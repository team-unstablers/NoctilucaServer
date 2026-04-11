//
//  noctiluca_vpx_decoder_shim.h
//  NoctilucaLibVPXDecoderShim
//
//  Thin C wrappers around libvpx decoder entry points that Swift cannot
//  reach directly (preprocessor macros, variadic controls).
//
//  This header intentionally does NOT include any <vpx/*> headers so that
//  Swift targets importing this module do not need libvpx's header search
//  path available to their Clang importer. libvpx-specific types remain
//  opaque (void *) here; the Swift side holds properly-typed
//  `UnsafeMutablePointer<vpx_codec_ctx_t>` via `import NoctilucaLibVPXDecoder`
//  and casts to raw pointers at the call site.
//

#ifndef NOCTILUCA_VPX_DECODER_SHIM_H
#define NOCTILUCA_VPX_DECODER_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/// Returns `VPX_DECODER_ABI_VERSION` as evaluated at C compile time.
/// Swift cannot reproduce this preprocessor expression
/// (it is `3 + (4 + 5)` through a macro chain), so callers must fetch the
/// value here and pass it to `vpx_codec_dec_init_ver(...)` directly (which
/// IS a real C function Swift can call).
int noctiluca_vpx_decoder_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif /* NOCTILUCA_VPX_DECODER_SHIM_H */
