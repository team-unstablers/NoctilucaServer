//
//  VPXVideoDecoder.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/12/26.
//

import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import SiriusKitClient

import NoctilucaLibVPXDecoder

/// VP8 video decoder backed by libvpx.
///
/// Rule G exception (media pipeline class): `@unchecked Sendable`. All mutable
/// state is serialized through `workerQueue.sync`, mirroring `VTVideoDecoder`.
final class VPXVideoDecoder: VideoDecoder, @unchecked Sendable {
    weak var delegate: VideoDecoderDelegate?

    private let logger = NoctilucaLogger(category: "VPXVideoDecoder", subsystem: "projection.decoder")
    private let workerQueue: DispatchQueue
    internal let callbackQueue: DispatchQueue

    private var configuration: VideoDecoderConfiguration?
    private var isStarted = false

    // MARK: libvpx state (heap-allocated for stable pointer)

    private var decoderCtx: UnsafeMutablePointer<vpx_codec_ctx_t>?
    private var sourceWidth: Int32 = 0
    private var sourceHeight: Int32 = 0

    /// Metadata captured when `decode()` enters the decoder, popped in the
    /// drain loop to attach to the emitted `DecodedFrame`. VP8 with a single-
    /// pass real-time configuration emits exactly one decoded picture per
    /// input frame in FIFO order, so a plain queue is sufficient.
    private struct PendingInput {
        let frameID: UInt64
        let pts: CMTime
        let isKeyframeHint: Bool
        let decodeStart: DispatchTime
    }
    private var pendingInputs: [PendingInput] = []

    var decoderTypeName: String { "libvpx (VP8)" }

    init() {
        self.workerQueue = DispatchQueue(
            label: NoctilucaMeta.scopedIdentifier("projection.decoder.VPXVideoDecoder.workerQueue"),
            qos: .userInitiated
        )
        self.callbackQueue = DispatchQueue(
            label: NoctilucaMeta.scopedIdentifier("projection.decoder.VPXVideoDecoder.callbackQueue"),
            qos: .userInitiated
        )
    }

    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
    }

    deinit {
        // Best-effort cleanup. stop() should normally run first, but a dropped
        // decoder without stop() must still release libvpx state.
        tearDownDecoderState()
    }

    // MARK: - VideoDecoder protocol

    func prepare(with configuration: VideoDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoDecoderError.alreadyPrepared
        }
        guard configuration.codec.fourCC == .vp80 else {
            throw VideoDecoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        self.configuration = configuration
    }

    func start() throws {
        guard configuration != nil else {
            throw VideoDecoderError.notPrepared
        }
        isStarted = true
    }

    func stop() throws {
        workerQueue.sync {
            if let ctx = decoderCtx {
                // Flush: passing NULL data signals end-of-stream.
                _ = vpx_codec_decode(ctx, nil, 0, nil, 0)
                drainDecodedImages()
            }
            tearDownDecoderState()
            isStarted = false
        }
    }

    func flush() throws {
        workerQueue.sync {
            guard let ctx = decoderCtx else { return }
            _ = vpx_codec_decode(ctx, nil, 0, nil, 0)
            drainDecodedImages()
        }
    }

    func decode(_ frame: EncodedFrameInput) throws {
        try workerQueue.sync {
            guard isStarted else { throw VideoDecoderError.notStarted }
            try ensureDecoderContext()
            guard let ctx = decoderCtx else { throw VideoDecoderError.notPrepared }

            let pts = CMTime(
                value: CMTimeValue(frame.header.presentationTimestamp),
                timescale: 1_000_000
            )
            let pending = PendingInput(
                frameID: frame.header.frameID,
                pts: pts,
                isKeyframeHint: frame.header.flags.contains(.isKeyframe),
                decodeStart: DispatchTime.now()
            )

            let status: vpx_codec_err_t = frame.data.withUnsafeBytes { raw in
                let base = raw.bindMemory(to: UInt8.self).baseAddress
                return vpx_codec_decode(ctx, base, UInt32(frame.data.count), nil, 0)
            }

            guard status == VPX_CODEC_OK else {
                logger.error("vpx_codec_decode failed frameID=\(pending.frameID) status=\(status.rawValue)")
                let error = VideoDecoderError.decompressionSessionFailed(OSStatus(status.rawValue))
                let decoder = self
                callbackQueue.async {
                    decoder.delegate?.videoDecoder(decoder, didFailWith: error)
                }
                return
            }

            pendingInputs.append(pending)
            drainDecodedImages()
        }
    }
}

// MARK: - Decoder lifecycle

private extension VPXVideoDecoder {
    func ensureDecoderContext() throws {
        if decoderCtx != nil { return }

        guard let configuration else { throw VideoDecoderError.notPrepared }
        guard let srSize = configuration.codec.size else {
            // Codec.size should always be populated when ProjectionSession.prepare
            // runs — it guards on size earlier. Fail hard if it is missing.
            throw VideoDecoderError.notPrepared
        }
        sourceWidth = Int32(srSize.width)
        sourceHeight = Int32(srSize.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw VideoDecoderError.invalidBitstream
        }

        guard let iface = vpx_codec_vp8_dx() else {
            logger.error("vpx_codec_vp8_dx() returned nil")
            throw VideoDecoderError.decompressionSessionFailed(-1)
        }

        var cfg = vpx_codec_dec_cfg_t()
        // Let libvpx use a few worker threads for motion compensation; cap at
        // `activeProcessorCount - 1` to leave a core for the renderer.
        let threadHint = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        cfg.threads = UInt32(min(threadHint, 8))
        cfg.w = UInt32(sourceWidth)
        cfg.h = UInt32(sourceHeight)

        let ctx = UnsafeMutablePointer<vpx_codec_ctx_t>.allocate(capacity: 1)
        ctx.initialize(to: vpx_codec_ctx_t())

        let abi = Int32(noctiluca_vpx_decoder_abi_version())
        let status = vpx_codec_dec_init_ver(ctx, iface, &cfg, 0, abi)
        guard status == VPX_CODEC_OK else {
            ctx.deinitialize(count: 1)
            ctx.deallocate()
            logger.error("vpx_codec_dec_init_ver failed status=\(status.rawValue)")
            throw VideoDecoderError.decompressionSessionFailed(OSStatus(status.rawValue))
        }

        decoderCtx = ctx
        logger.info("VPX decoder initialized \(self.sourceWidth)x\(self.sourceHeight) threads=\(cfg.threads)")
    }

    func tearDownDecoderState() {
        if let ctx = decoderCtx {
            _ = vpx_codec_destroy(ctx)
            ctx.deinitialize(count: 1)
            ctx.deallocate()
            decoderCtx = nil
        }
        pendingInputs.removeAll()
    }
}

// MARK: - Output drain

private extension VPXVideoDecoder {
    func drainDecodedImages() {
        guard let ctx = decoderCtx else { return }
        var iter: vpx_codec_iter_t? = nil
        while let imgPtr = vpx_codec_get_frame(ctx, &iter) {
            // `imgPtr` points at decoder-internal storage that is only valid
            // until the next `vpx_codec_decode` call, so we must copy out
            // the pixels into a fresh CVPixelBuffer before returning.
            let img = imgPtr.pointee
            guard img.fmt == VPX_IMG_FMT_I420 else {
                logger.warning("unexpected vpx_image fmt \(img.fmt.rawValue)")
                continue
            }

            let width = Int(img.d_w)
            let height = Int(img.d_h)
            guard width > 0, height > 0 else { continue }

            let pixelBuffer: CVPixelBuffer
            do {
                pixelBuffer = try makeNV12PixelBuffer(width: width, height: height)
            } catch {
                logger.error("failed to allocate NV12 pixel buffer: \(error)")
                let decoder = self
                let err = error
                callbackQueue.async {
                    decoder.delegate?.videoDecoder(decoder, didFailWith: err)
                }
                continue
            }

            copyI420ToNV12(source: imgPtr, destination: pixelBuffer)

            guard !pendingInputs.isEmpty else {
                logger.warning("received VPX picture without a pending input entry")
                continue
            }
            let pending = pendingInputs.removeFirst()

            let formatDescription: CMFormatDescription
            do {
                formatDescription = try CMFormatDescription(imageBuffer: pixelBuffer)
            } catch {
                logger.error("CMFormatDescription(imageBuffer:) failed: \(error)")
                let decoder = self
                let err = error
                callbackQueue.async {
                    decoder.delegate?.videoDecoder(decoder, didFailWith: err)
                }
                continue
            }

            let decodeEnd = DispatchTime.now()
            let decodeMs = max(
                0,
                Double(decodeEnd.uptimeNanoseconds - pending.decodeStart.uptimeNanoseconds) / 1_000_000.0
            )

            let decoded = DecodedFrame(
                pixelBuffer: pixelBuffer,
                pts: pending.pts,
                isKeyFrame: pending.isKeyframeHint,
                formatDescription: formatDescription,
                decodeTimeMs: decodeMs
            )

            let decoder = self
            callbackQueue.async {
                decoder.delegate?.videoDecoder(decoder, didDecode: decoded)
            }
        }
    }
}

// MARK: - CVPixelBuffer creation + I420 → NV12 conversion

private extension VPXVideoDecoder {
    func makeNV12PixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any,
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            throw VideoDecoderError.decompressionSessionFailed(OSStatus(status))
        }
        return pixelBuffer
    }

    func copyI420ToNV12(source imgPtr: UnsafePointer<vpx_image_t>, destination pb: CVPixelBuffer) {
        let lockFlags = CVPixelBufferLockFlags(rawValue: 0) // write lock
        let lockResult = CVPixelBufferLockBaseAddress(pb, lockFlags)
        guard lockResult == kCVReturnSuccess else {
            logger.error("CVPixelBufferLockBaseAddress failed \(lockResult)")
            return
        }
        defer { CVPixelBufferUnlockBaseAddress(pb, lockFlags) }

        let img = imgPtr.pointee
        let width = Int(img.d_w)
        let height = Int(img.d_h)
        let chromaWidth = width / 2
        let chromaHeight = height / 2

        // vpx_image_t exposes C fixed-size arrays as Swift tuples:
        //   planes[4] → (.0 ... .3), stride[4] → (.0 ... .3)
        guard let ySrc = img.planes.0,
              let uSrc = img.planes.1,
              let vSrc = img.planes.2
        else {
            logger.error("vpx_image_t missing Y/U/V plane pointers")
            return
        }
        let ySrcStride = Int(img.stride.0)
        let uSrcStride = Int(img.stride.1)
        let vSrcStride = Int(img.stride.2)

        guard let yDstBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0)?.assumingMemoryBound(to: UInt8.self),
              let uvDstBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1)?.assumingMemoryBound(to: UInt8.self)
        else {
            logger.error("CVPixelBufferGetBaseAddressOfPlane returned nil")
            return
        }
        let yDstStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let uvDstStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)

        // Y plane — row-by-row memcpy (source/dest strides may both be padded).
        for row in 0..<height {
            let src = ySrc.advanced(by: row * ySrcStride)
            let dst = yDstBase.advanced(by: row * yDstStride)
            memcpy(dst, src, width)
        }

        // UV plane — interleave U and V into [U V U V ...]. Exact inverse of
        // the server-side `VPXVideoEncoder.copyNV12Planes` de-interleave path.
        for row in 0..<chromaHeight {
            let uRow = uSrc.advanced(by: row * uSrcStride)
            let vRow = vSrc.advanced(by: row * vSrcStride)
            let dstRow = uvDstBase.advanced(by: row * uvDstStride)
            var col = 0
            while col < chromaWidth {
                dstRow[col * 2] = uRow[col]
                dstRow[col * 2 + 1] = vRow[col]
                col += 1
            }
        }
    }
}
