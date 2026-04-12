//
//  noctiluca_vpx_shim.h
//  NoctilucaLibVPXShim
//
//  Thin C wrappers that expose libvpx entry points which are inaccessible
//  from Swift because they are declared as preprocessor macros or as C
//  variadic functions.
//
//  NOTE: This header intentionally does NOT include any <vpx/*> headers, so
//  that Swift targets which import this module do not need libvpx's header
//  search path available to their Clang importer. All libvpx-specific types
//  are opaque to the caller here (void *) and the Swift side casts the
//  properly-typed pointers (vpx_codec_ctx_t *, vpx_codec_iface_t * ...)
//  to raw pointers at the call site.
//

#ifndef NOCTILUCA_VPX_SHIM_H
#define NOCTILUCA_VPX_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/// Returns `VPX_ENCODER_ABI_VERSION` as evaluated at C compile time.
/// Swift cannot reproduce this preprocessor expression, so callers must
/// fetch the value here and pass it to `vpx_codec_enc_init_ver(...)`
/// directly (which IS a real C function Swift can call).
int noctiluca_vpx_encoder_abi_version(void);

/// Typed wrapper around the variadic `vpx_codec_control_(...)` for `int`
/// controls such as `VP8E_SET_CPUUSED`.
///
/// - Parameters:
///   - ctx:   Pointer to `vpx_codec_ctx_t` (cast from Swift as raw pointer).
///   - ctrlId: The control id (e.g. `VP8E_SET_CPUUSED.rawValue`).
///   - value: The control argument interpreted as `int`.
/// - Returns: `vpx_codec_err_t` as `int` (use `VPX_CODEC_OK == 0`).
int noctiluca_vpx_codec_control_int(void *ctx, int ctrlId, int value);

/// Typed wrapper around the variadic `vpx_codec_control_(...)` for
/// `unsigned int` controls such as `VP8E_SET_STATIC_THRESHOLD`.
int noctiluca_vpx_codec_control_uint(void *ctx, int ctrlId, unsigned int value);

#ifdef __cplusplus
}
#endif

#endif /* NOCTILUCA_VPX_SHIM_H */
