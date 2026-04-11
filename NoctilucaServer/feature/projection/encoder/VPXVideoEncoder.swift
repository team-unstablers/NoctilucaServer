//
//  VPXVideoEncoder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/12/26.
//

import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import SiriusKit

@preconcurrency import Accelerate

import NoctilucaLibVPX

/// VP8 video encoder backed by libvpx.
///
/// `@unchecked Sendable`: all mutable state is serialized through `workerQueue.sync`,
/// following the same pattern as `VTVideoEncoder`.
final class VPXVideoEncoder: VideoEncoder, @unchecked Sendable {
    private let logger = NoctilucaLogger(category: "VPXVideoEncoder")
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue

    private let defaultTargetBitrateKbps = 1200
    private let defaultMaxBitrateKbps = 2400

    private(set) var quality: SiriusKit.Codec.Quality?

    fileprivate var configuration: VideoEncoderConfiguration?

    // MARK: libvpx state

    /// Heap-allocated to guarantee a stable pointer across calls. Nil until
    /// `ensureEncoderContext(for:)` succeeds.
    private var encoderCtx: UnsafeMutablePointer<vpx_codec_ctx_t>?

    /// Latest encoder configuration. Kept around so `vpx_codec_enc_config_set`
    /// can be called with an updated copy when bitrate is adjusted at runtime.
    private var encoderCfg = vpx_codec_enc_cfg_t()

    /// Reusable YV12 image descriptor filled per frame.
    private var vpxImage: UnsafeMutablePointer<vpx_image_t>?

    private var sourceWidth: Int32 = 0
    private var sourceHeight: Int32 = 0

    private var isStarted = false
    private var pendingForceKeyframe = false
    private var targetBitrateKbps: Int
    private var maxBitrateKbps: Int

    /// VP8 with `g_lag_in_frames == 0` emits exactly one packet per encoded
    /// frame in FIFO order, so a plain queue of source `frameID`s is enough
    /// to reassociate each output packet with its upstream frame. The real
    /// presentation timestamp travels through libvpx itself (see the
    /// `g_timebase` discussion in `ensureEncoderContext(for:)`) and is
    /// recovered from `vpx_codec_cx_pkt_t.data.frame.pts`, so we do NOT need
    /// to stash CMTime values in this queue.
    private var pendingFrameIDs: [UInt64] = []

    /// Cached per-frame duration in microseconds, computed as
    /// `1_000_000 / framesPerSecond` at encoder-context init time. libvpx
    /// uses this value together with the microsecond-scaled PTS to compute
    /// per-frame rate-control budgets. On a variable-frame-rate source the
    /// real gap between frames can be much larger than this, which is fine:
    /// libvpx reads the actual elapsed time from the monotonically growing
    /// PTS and grants the extra budget accordingly.
    private var encodedFrameDurationMicros: UInt = 33_333

    /// Cached vImage BGRA→I420 변환 정보. preferredColorRange는 prepare() 이후
    /// 변하지 않으므로 인코더 컨텍스트 수명 동안 재사용한다. releaseEncoderState()
    /// 에서 nil로 되돌려 다음 init 때 새 colorRange가 반영되도록 한다.
    private var cachedArgbToYpCbCrInfo: vImage_ARGBToYpCbCr?

    /// 코덱 협상 결과(`sourceWidth/Height`)와 원본 CVPixelBuffer 크기가 다를 때
    /// BGRA → BGRA 리스케일 결과를 담는 캐시 버퍼. dst 크기는 인코더 수명 동안
    /// 고정이라 한 번만 할당하고 매 프레임 재사용한다. `data`는 vImageBuffer_Init
    /// 가 malloc으로 할당하므로 release 시 직접 free 해줘야 한다.
    private var scaledBgraBuffer: vImage_Buffer?

    /// `vImageScale_ARGB8888`이 내부 작업용으로 요구하는 scratch 버퍼.
    /// 필요한 크기는 (src, dst) 쌍에 따라 결정되므로, src 해상도가 바뀌면
    /// 다시 쿼리해 재할당한다.
    private var scaleTempBuffer: UnsafeMutableRawPointer?
    private var scaleTempBufferSize: Int = 0
    private var cachedScaleSrcWidth: Int = 0
    private var cachedScaleSrcHeight: Int = 0

    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation

    init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.vpx.worker", qos: .userInitiated)
        self.callbackQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.vpx.callback", qos: .userInitiated)
        self.targetBitrateKbps = defaultTargetBitrateKbps
        self.maxBitrateKbps = defaultMaxBitrateKbps

        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        self.continuation = continuationLocal
    }

    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
        self.targetBitrateKbps = defaultTargetBitrateKbps
        self.maxBitrateKbps = defaultMaxBitrateKbps

        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        self.continuation = continuationLocal
    }

    deinit {
        // Best-effort cleanup. stop() should normally run first, but a dropped
        // encoder without stop() must still release libvpx state.
        releaseEncoderState()
    }

    // MARK: - VideoEncoder protocol

    func prepare(with configuration: VideoEncoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoEncoderError.alreadyPrepared
        }
        guard configuration.codec.fourCC == .vp80 else {
            throw VideoEncoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        self.configuration = configuration
        self.quality = configuration.codec.quality
    }

    func start() throws {
        guard configuration != nil else {
            throw VideoEncoderError.notPrepared
        }
        isStarted = true
    }

    func stop() throws {
        // Follow VTVideoEncoder's "seize ownership under lock, tear down outside
        // the lock" pattern so nothing we call into libvpx can re-enter the same
        // workerQueue.
        let shouldTeardown = workerQueue.sync { () -> Bool in
            let wasStarted = isStarted
            isStarted = false
            return wasStarted
        }

        if shouldTeardown {
            workerQueue.sync {
                // Flush any in-flight data before tearing the context down.
                if let ctx = encoderCtx {
                    _ = vpx_codec_encode(ctx, nil, 0, 0, 0, vpxRealtimeDeadline)
                    drainEncodedPackets()
                }
                releaseEncoderState()
            }
        }

        continuation.finish()
    }

    func flush() throws {
        workerQueue.sync {
            guard let ctx = encoderCtx else { return }
            _ = vpx_codec_encode(ctx, nil, 0, 0, 0, vpxRealtimeDeadline)
            drainEncodedPackets()
        }
    }

    func encode(frameID: UInt64, sampleBuffer: CMSampleBuffer) throws {
        // Entry-time validity checks run on the caller's thread. Anything
        // that can actually block (I420 conversion + libvpx encode) moves
        // onto `workerQueue.async` below, so the caller (ScreenCaptureKit
        // delegate / ProjectionSession task) is never held up by a
        // multi-millisecond software encode call.
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        guard isStarted else {
            throw VideoEncoderError.notStarted
        }

        // NOTE: libvpx is a synchronous CPU-bound encoder (unlike
        // VideoToolbox, which is a hardware-async callback API). Holding
        // `workerQueue.sync` across `vpx_codec_encode` would:
        //
        //   1. Block ScreenCaptureKit's delivery thread, causing upstream
        //      frame drops or jitter.
        //   2. Starve the AsyncStream consumer — the same cooperative
        //      executor that drives `for await event in encoder.events`
        //      ends up parked waiting on us — so emitted packets sit in
        //      the stream buffer for many milliseconds before anyone
        //      picks them up.
        //
        // Dispatching the heavy work asynchronously mirrors what
        // WebPVideoEncoder does for the same reason.
        workerQueue.async { [self] in
            // Re-check inside the worker queue. stop() may have flipped
            // `isStarted` to false between the caller's check and the
            // moment this block actually runs.
            guard self.isStarted else { return }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                self.continuation.yield(.errorOccurred(VideoEncoderError.invalidSampleBuffer))
                return
            }

            do {
                try self.ensureEncoderContext(for: imageBuffer)
            } catch {
                self.continuation.yield(.errorOccurred(error))
                return
            }

            guard let ctx = self.encoderCtx, let img = self.vpxImage else {
                self.continuation.yield(.errorOccurred(VideoEncoderError.notPrepared))
                return
            }

            do {
                try self.fillVPXImage(from: imageBuffer, destination: img)
            } catch {
                self.continuation.yield(.errorOccurred(error))
                return
            }

            let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let ptsMicros = self.microseconds(from: originalPTS)

            let shouldForceKeyframe = self.pendingForceKeyframe
            self.pendingForceKeyframe = false
            let frameFlags: vpx_enc_frame_flags_t = shouldForceKeyframe ? self.vpxForceKeyframeFlag : 0

            self.pendingFrameIDs.append(frameID)

            let status = vpx_codec_encode(
                ctx,
                img,
                vpx_codec_pts_t(ptsMicros),
                self.encodedFrameDurationMicros,
                frameFlags,
                self.vpxRealtimeDeadline
            )

            if status != VPX_CODEC_OK {
                // Roll back state on failure.
                if !self.pendingFrameIDs.isEmpty {
                    self.pendingFrameIDs.removeLast()
                }
                if shouldForceKeyframe {
                    self.pendingForceKeyframe = true
                }
                self.logger.error("vpx_codec_encode failed status=\(status.rawValue)")
                self.continuation.yield(.errorOccurred(
                    VideoEncoderError.compressionSessionFailed(OSStatus(status.rawValue))
                ))
                return
            }

            self.drainEncodedPackets()
        }
    }

    // MARK: - On-the-fly controls

    func forceKeyframe() {
        workerQueue.async {
            self.pendingForceKeyframe = true
        }
    }

    @discardableResult
    func updateTargetBitrate(_ bitrateKbps: Int) -> Bool {
        guard bitrateKbps > 0 else {
            logger.error("Target bitrate must be positive (kbps=\(bitrateKbps))")
            return false
        }
        var success = false
        workerQueue.sync {
            self.targetBitrateKbps = bitrateKbps
            guard let ctx = self.encoderCtx else {
                // Encoder not yet created — value will be picked up on next init.
                success = true
                return
            }
            self.encoderCfg.rc_target_bitrate = UInt32(bitrateKbps)
            let status = vpx_codec_enc_config_set(ctx, &self.encoderCfg)
            if status != VPX_CODEC_OK {
                self.logger.error("vpx_codec_enc_config_set failed status=\(status.rawValue)")
                success = false
                return
            }
            success = true
        }
        return success
    }

    @discardableResult
    func updateMaxBitrate(bitrateKbps: Int) -> Bool {
        // VP8 in libvpx has no direct analog to VideoToolbox's DataRateLimits.
        // Keep the requested value for bookkeeping but do not reconfigure the
        // codec. The effective cap is still controlled by `rc_target_bitrate`
        // plus the VBV buffer parameters set in `ensureEncoderContext`.
        guard bitrateKbps > 0 else { return false }
        workerQueue.sync {
            self.maxBitrateKbps = bitrateKbps
        }
        return true
    }

    static func isSupported(codec: CodecSpecification) -> Bool {
        return codec.fourCC == .vp80
    }
}

// MARK: - Encoder lifecycle

private extension VPXVideoEncoder {
    func ensureEncoderContext(for imageBuffer: CVPixelBuffer) throws {
        if encoderCtx != nil { return }

        guard let configuration else { throw VideoEncoderError.notPrepared }
        let codec = configuration.codec

        let size = codec.size?.cgSize ?? CGSize(
            width: CGFloat(CVPixelBufferGetWidth(imageBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(imageBuffer))
        )
        sourceWidth = Int32(size.width)
        sourceHeight = Int32(size.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw VideoEncoderError.invalidDimensions
        }

        guard let iface = vpx_codec_vp8_cx() else {
            logger.error("vpx_codec_vp8_cx() returned nil")
            throw VideoEncoderError.compressionSessionFailed(-1)
        }

        var cfg = vpx_codec_enc_cfg_t()
        let defaultStatus = vpx_codec_enc_config_default(iface, &cfg, 0)
        guard defaultStatus == VPX_CODEC_OK else {
            logger.error("vpx_codec_enc_config_default failed status=\(defaultStatus.rawValue)")
            throw VideoEncoderError.compressionSessionFailed(OSStatus(defaultStatus.rawValue))
        }

        // Microsecond timebase. libvpx's rate controller computes the
        // per-frame byte budget as `duration_ticks / timebase × rc_target_bitrate / 8`,
        // so two independent values must be chosen correctly:
        //
        //   1. `g_timebase` defines the tick resolution. We keep it at
        //      1 µs so that real CMSampleBuffer timestamps can be passed
        //      to `vpx_codec_encode` verbatim.
        //
        //   2. The `duration` argument of `vpx_codec_encode` is the *nominal*
        //      on-screen time this frame occupies, not the wall-clock gap
        //      since the previous frame. Using `duration = 1` with a
        //      microsecond timebase makes the rate controller think each
        //      frame lasts 1 µs and the per-frame budget collapses to ~0
        //      bytes, which looks like frames only coming out every several
        //      dozen seconds.
        //
        // The correct value for `duration` is `1_000_000 / fps` (one frame
        // period). On a variable-frame-rate source — like an idle remote
        // desktop — the genuine gap between two frames may be much larger
        // than `1 / fps`, but that is not a problem: libvpx reads the real
        // elapsed time from the strictly increasing PTS and hands the extra
        // budget back to the VBV accumulator, so a long pause does not
        // starve the encoder when the next frame finally arrives.
        var framesPerSecond: Int32 = 60
        if let rate = codec.frameRate, rate > 0 {
            framesPerSecond = Int32(rate.rounded())
            if framesPerSecond <= 0 { framesPerSecond = 60 }
        }
        
        framesPerSecond = 60
        
        encodedFrameDurationMicros = UInt(1_000_000 / framesPerSecond)

        cfg.g_w = UInt32(sourceWidth)
        cfg.g_h = UInt32(sourceHeight)
        cfg.g_timebase = vpx_rational_t(num: 1, den: 1_000_000)
        cfg.g_pass = VPX_RC_ONE_PASS
        cfg.g_lag_in_frames = 0
        // cfg.g_threads = 2
        cfg.g_error_resilient = 1
        cfg.kf_mode = VPX_KF_AUTO
        cfg.kf_min_dist = 0
        
        // cfg.rc_dropframe_thresh = 30
        
        // Match VTVideoEncoder's ~4-second keyframe interval. `kf_max_dist`
        // counts input frames, not ticks, so this stays expressed in frames.
        cfg.kf_max_dist = UInt32(framesPerSecond * 4)

        applyQualityMapping(to: &cfg, codec: codec)

        let ctx = UnsafeMutablePointer<vpx_codec_ctx_t>.allocate(capacity: 1)
        ctx.initialize(to: vpx_codec_ctx_t())

        // Use vpx_codec_enc_init_ver directly, fetching VPX_ENCODER_ABI_VERSION
        // from the C shim (the macro cannot be evaluated in Swift).
        let abiVersion = Int32(noctiluca_vpx_encoder_abi_version())
        let initStatus = vpx_codec_enc_init_ver(ctx, iface, &cfg, 0, abiVersion)
        if initStatus != VPX_CODEC_OK {
            ctx.deinitialize(count: 1)
            ctx.deallocate()
            logger.error("vpx_codec_enc_init_ver failed status=\(initStatus.rawValue)")
            throw VideoEncoderError.compressionSessionFailed(OSStatus(initStatus.rawValue))
        }

        // Real-time tuning. Cast ctx to a raw pointer for the shim so it does
        // not need to know about libvpx types.
        let rawCtx = UnsafeMutableRawPointer(ctx)
        let cpuUsedStatus = noctiluca_vpx_codec_control_int(rawCtx, Int32(VP8E_SET_CPUUSED.rawValue), -4)
        if cpuUsedStatus != 0 {
            logger.warning("VP8E_SET_CPUUSED failed status=\(cpuUsedStatus)")
        }
        let staticThreshStatus = noctiluca_vpx_codec_control_uint(rawCtx, Int32(VP8E_SET_STATIC_THRESHOLD.rawValue), 200)
        if staticThreshStatus != 0 {
            logger.warning("VP8E_SET_STATIC_THRESHOLD failed status=\(staticThreshStatus)")
        }
        
        let partitionStatus = noctiluca_vpx_codec_control_int(rawCtx, Int32(VP8E_SET_TOKEN_PARTITIONS.rawValue), 4)
        if partitionStatus != 0 {
            logger.warning("VP8E_SET_TOKEN_PARTITIONS failed status=\(partitionStatus)")
        }

        // Allocate the reusable I420 image descriptor. vpx_img_alloc() with
        // align=1 produces tightly-packed strides.
        guard let img = vpx_img_alloc(nil, VPX_IMG_FMT_I420, UInt32(sourceWidth), UInt32(sourceHeight), 1) else {
            _ = vpx_codec_destroy(ctx)
            ctx.deinitialize(count: 1)
            ctx.deallocate()
            logger.error("vpx_img_alloc failed")
            throw VideoEncoderError.compressionSessionFailed(-1)
        }

        encoderCtx = ctx
        encoderCfg = cfg
        vpxImage = img

        logger.info("VPX encoder initialized \(self.sourceWidth)x\(self.sourceHeight) target=\(self.targetBitrateKbps)kbps")
    }

    func releaseEncoderState() {
        if let ctx = encoderCtx {
            _ = vpx_codec_destroy(ctx)
            ctx.deinitialize(count: 1)
            ctx.deallocate()
            encoderCtx = nil
        }
        if let img = vpxImage {
            vpx_img_free(img)
            vpxImage = nil
        }
        pendingFrameIDs.removeAll()
        cachedArgbToYpCbCrInfo = nil

        if let buf = scaledBgraBuffer, let data = buf.data {
            free(data)
        }
        scaledBgraBuffer = nil

        if let temp = scaleTempBuffer {
            free(temp)
        }
        scaleTempBuffer = nil
        scaleTempBufferSize = 0
        cachedScaleSrcWidth = 0
        cachedScaleSrcHeight = 0
    }
}

// MARK: - Quality mapping

private extension VPXVideoEncoder {
    func applyQualityMapping(to cfg: inout vpx_codec_enc_cfg_t, codec: SiriusKit.Codec) {
        switch codec.quality {
        case .constantBitrate(let bitrateKbps):
            targetBitrateKbps = Int(bitrateKbps)
            maxBitrateKbps = Int(bitrateKbps)
            cfg.rc_end_usage = VPX_CBR
            cfg.rc_target_bitrate = UInt32(max(bitrateKbps, 1))

        case .variableBitrate(let targetKbps, let maxKbps):
            targetBitrateKbps = Int(targetKbps)
            maxBitrateKbps = Int(maxKbps)
            cfg.rc_end_usage = VPX_VBR
            cfg.rc_target_bitrate = UInt32(max(targetKbps, 1))

        case .fixedQuality(let factor):
            let clamped = max(0, min(Int(factor), 100))
            // Map 0..100 → VP8 qp range 63..0 (lower qp = higher quality).
            let maxQP = UInt32((100 - clamped) * 63 / 100)
            cfg.rc_end_usage = VPX_CQ
            cfg.rc_target_bitrate = UInt32(defaultMaxBitrateKbps)
            cfg.rc_min_quantizer = 0
            cfg.rc_max_quantizer = maxQP

        case .lossless:
            // VP8 does not support lossless; fall back to the highest-quality
            // CQ preset and warn.
            logger.warning("VP8 does not support lossless; falling back to high-quality CQ")
            cfg.rc_end_usage = VPX_CQ
            cfg.rc_target_bitrate = UInt32(defaultMaxBitrateKbps)
            cfg.rc_min_quantizer = 0
            cfg.rc_max_quantizer = 4

        case .auto:
            // AutoQualityPlanner will drive `updateTargetBitrate(_:)` after start.
            targetBitrateKbps = defaultTargetBitrateKbps
            maxBitrateKbps = defaultMaxBitrateKbps
            cfg.rc_end_usage = VPX_VBR
            cfg.rc_target_bitrate = UInt32(defaultTargetBitrateKbps)
        }
    }
}

// MARK: - CVPixelBuffer → I420

private extension VPXVideoEncoder {
    /// `codec.option(.colorRange)` 기본값은 VTVideoEncoder와 동일하게 limited range.
    /// BGRA → YUV 변환 매트릭스 선택과 NV12 경로의 포맷 일치성 검증에 사용한다.
    var preferredColorRange: CodecOptionValue {
        configuration?.codec.option(.colorRange) ?? .kColorRangeLimited
    }

    func fillVPXImage(from imageBuffer: CVPixelBuffer, destination img: UnsafeMutablePointer<vpx_image_t>) throws {
        let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            try convert(bgra: imageBuffer, i420: img)

        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // NV12(VideoRange) → I420. 비트를 그대로 복사하므로 range가 자동 보존되지만,
            // 사용자가 요청한 colorRange 옵션과 실제 소스 포맷이 다르면 경고를 남긴다.
            if preferredColorRange == .kColorRangeFull {
                logger.warning("Source is NV12 videoRange but codec option requests full range; frame will be encoded as limited range")
            }
            try copyNV12Planes(from: imageBuffer, destination: img)

        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            if preferredColorRange == .kColorRangeLimited {
                logger.warning("Source is NV12 fullRange but codec option requests limited range; frame will be encoded as full range")
            }
            try copyNV12Planes(from: imageBuffer, destination: img)

        default:
            logger.error("Unsupported pixel format 0x\(String(pixelFormat, radix: 16)) for VPXVideoEncoder")
            throw VideoEncoderError.invalidSampleBuffer
        }
    }

    func convert(bgra imageBuffer: CVPixelBuffer, i420 img: UnsafeMutablePointer<vpx_image_t>) throws {
        let lockFlags = CVPixelBufferLockFlags.readOnly
        let lockResult = CVPixelBufferLockBaseAddress(imageBuffer, lockFlags)
        guard lockResult == kCVReturnSuccess else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, lockFlags) }

        guard let base = CVPixelBufferGetBaseAddress(imageBuffer) else {
            throw VideoEncoderError.invalidSampleBuffer
        }

        // CVPixelBuffer는 우측에 패딩이 붙는 경우가 있으므로 logical width/height를
        // 변환 extent로 쓰고, 실제 row stride는 그대로 전달한다.
        let rgbStride = CVPixelBufferGetBytesPerRow(imageBuffer)
        let srcW = CVPixelBufferGetWidth(imageBuffer)
        let srcH = CVPixelBufferGetHeight(imageBuffer)

        // 코덱 협상으로 결정된 출력 크기. vpx_img_alloc도 동일한 크기로 잡혀 있다.
        let dstW = Int(sourceWidth)
        let dstH = Int(sourceHeight)
        let chromaW = dstW / 2
        let chromaH = dstH / 2

        guard let yDest = img.pointee.planes.0,
              let uDest = img.pointee.planes.1,
              let vDest = img.pointee.planes.2
        else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        let yDestStride = Int(img.pointee.stride.0)
        let uDestStride = Int(img.pointee.stride.1)
        let vDestStride = Int(img.pointee.stride.2)

        // 1) 원본 CVPixelBuffer를 서술하는 vImage_Buffer.
        var srcBuffer = vImage_Buffer(
            data: base,
            height: vImagePixelCount(srcH),
            width: vImagePixelCount(srcW),
            rowBytes: rgbStride
        )

        // 2) 원본 해상도와 출력 해상도가 다르면 BGRA 단계에서 Lanczos 리샘플로
        //    먼저 dst 크기까지 줄여 둔다. YUV 변환 단계는 항상 dst 크기에서 동작
        //    하므로 chroma plane 정렬 문제가 사라지고, 변환 호출도 한 번이면 충분.
        if srcW != dstW || srcH != dstH {
            try ensureScaleResources(srcWidth: srcW, srcHeight: srcH)
            guard var scaled = scaledBgraBuffer else {
                throw VideoEncoderError.invalidSampleBuffer
            }
            let scaleErr = vImageScale_ARGB8888(
                &srcBuffer,
                &scaled,
                scaleTempBuffer,
                vImage_Flags(kvImageHighQualityResampling)
            )
            guard scaleErr == kvImageNoError else {
                logger.error("vImageScale_ARGB8888 failed err=\(scaleErr)")
                throw VideoEncoderError.invalidSampleBuffer
            }
            srcBuffer = scaled
        }

        // 3) Y/Cb/Cr destination descriptors. vpx_img는 dst 크기로 alloc되어
        //    있으므로 width/height 모두 dst 기준으로 잡는다.
        var yBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(yDest),
            height: vImagePixelCount(dstH),
            width: vImagePixelCount(dstW),
            rowBytes: yDestStride
        )
        var cbBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(uDest),
            height: vImagePixelCount(chromaH),
            width: vImagePixelCount(chromaW),
            rowBytes: uDestStride
        )
        var crBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(vDest),
            height: vImagePixelCount(chromaH),
            width: vImagePixelCount(chromaW),
            rowBytes: vDestStride
        )

        var info = try ensureArgbToYpCbCrInfo()

        // vImageConvert_ARGB8888To420Yp8_Cb8_Cr8는 소스 채널을 ARGB 순서
        // (A=0, R=1, G=2, B=3)로 해석한다. 32BGRA(B=0, G=1, R=2, A=3)의 메모리
        // 레이아웃을 그대로 읽도록 permuteMap[3, 2, 1, 0]을 전달해 채널을 재배열한다.
        let permuteMap: [UInt8] = [3, 2, 1, 0]
        let err = permuteMap.withUnsafeBufferPointer { permPtr -> vImage_Error in
            vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(
                &srcBuffer,
                &yBuffer,
                &cbBuffer,
                &crBuffer,
                &info,
                permPtr.baseAddress!,
                vImage_Flags(kvImageNoFlags)
            )
        }

        guard err == kvImageNoError else {
            logger.error("vImageConvert_ARGB8888To420Yp8_Cb8_Cr8 failed err=\(err)")
            throw VideoEncoderError.invalidSampleBuffer
        }
    }

    /// BGRA 리스케일 경로에서 사용할 캐시 자원(dst 버퍼 + Lanczos scratch buffer)
    /// 을 lazily 준비한다. dst 버퍼는 인코더 수명 동안 고정이고, scratch 버퍼는
    /// (src, dst) 쌍에 따라 크기가 달라지므로 src 해상도가 바뀌면 다시 쿼리한다.
    func ensureScaleResources(srcWidth: Int, srcHeight: Int) throws {
        let dstW = Int(sourceWidth)
        let dstH = Int(sourceHeight)
        guard dstW > 0, dstH > 0 else {
            throw VideoEncoderError.invalidDimensions
        }

        if scaledBgraBuffer == nil {
            var buf = vImage_Buffer()
            let initErr = vImageBuffer_Init(
                &buf,
                vImagePixelCount(dstH),
                vImagePixelCount(dstW),
                32, // bitsPerPixel for ARGB8888 (4 channels × 8-bit)
                vImage_Flags(kvImageNoFlags)
            )
            guard initErr == kvImageNoError else {
                logger.error("vImageBuffer_Init failed err=\(initErr)")
                throw VideoEncoderError.compressionSessionFailed(OSStatus(initErr))
            }
            scaledBgraBuffer = buf
        }

        let needsTempRequery = scaleTempBuffer == nil
            || cachedScaleSrcWidth != srcWidth
            || cachedScaleSrcHeight != srcHeight

        if needsTempRequery {
            if let oldTemp = scaleTempBuffer {
                free(oldTemp)
                scaleTempBuffer = nil
                scaleTempBufferSize = 0
            }

            // kvImageGetTempBufferSize 모드에서는 함수 반환값이 음수면 에러,
            // 0이면 scratch 불필요, 양수면 그만큼의 바이트가 필요하다는 뜻.
            var srcDescriptor = vImage_Buffer(
                data: nil,
                height: vImagePixelCount(srcHeight),
                width: vImagePixelCount(srcWidth),
                rowBytes: srcWidth * 4
            )
            var dstDescriptor = scaledBgraBuffer!
            let querySize = vImageScale_ARGB8888(
                &srcDescriptor,
                &dstDescriptor,
                nil,
                vImage_Flags(kvImageGetTempBufferSize | kvImageHighQualityResampling)
            )
            if querySize < 0 {
                logger.error("vImageScale_ARGB8888 temp buffer query failed err=\(querySize)")
                throw VideoEncoderError.compressionSessionFailed(OSStatus(querySize))
            }
            if querySize > 0 {
                guard let allocated = malloc(Int(querySize)) else {
                    logger.error("malloc failed for scale temp buffer size=\(querySize)")
                    throw VideoEncoderError.compressionSessionFailed(-1)
                }
                scaleTempBuffer = allocated
                scaleTempBufferSize = Int(querySize)
            }

            cachedScaleSrcWidth = srcWidth
            cachedScaleSrcHeight = srcHeight
            logger.info("VPX scaler ready src=\(srcWidth)x\(srcHeight) dst=\(dstW)x\(dstH) tempBytes=\(self.scaleTempBufferSize)")
        }
    }

    /// vImage 변환 정보(`vImage_ARGBToYpCbCr`)를 lazily 생성해 캐시한다.
    /// preferredColorRange는 prepare() 이후 변하지 않으므로 인코더 컨텍스트
    /// 수명 동안 동일한 정보를 재사용해도 안전하다.
    func ensureArgbToYpCbCrInfo() throws -> vImage_ARGBToYpCbCr {
        if let cached = cachedArgbToYpCbCrInfo {
            return cached
        }

        // VT 인코더가 사용하는 Rec.709 계수에 맞춰 limited / full range를 분기.
        var pixelRange: vImage_YpCbCrPixelRange
        if preferredColorRange == .kColorRangeFull {
            pixelRange = vImage_YpCbCrPixelRange(
                Yp_bias: 0, CbCr_bias: 128,
                YpRangeMax: 255, CbCrRangeMax: 255,
                YpMax: 255, YpMin: 0,
                CbCrMax: 255, CbCrMin: 0
            )
        } else {
            pixelRange = vImage_YpCbCrPixelRange(
                Yp_bias: 16, CbCr_bias: 128,
                YpRangeMax: 235, CbCrRangeMax: 240,
                YpMax: 235, YpMin: 16,
                CbCrMax: 240, CbCrMin: 16
            )
        }

        var info = vImage_ARGBToYpCbCr()
        let setupErr = vImageConvert_ARGBToYpCbCr_GenerateConversion(
            kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
            &pixelRange,
            &info,
            kvImageARGB8888,
            kvImage420Yp8_Cb8_Cr8,
            vImage_Flags(kvImageNoFlags)
        )

        guard setupErr == kvImageNoError else {
            logger.error("vImageConvert_ARGBToYpCbCr_GenerateConversion failed err=\(setupErr)")
            throw VideoEncoderError.compressionSessionFailed(OSStatus(setupErr))
        }

        cachedArgbToYpCbCrInfo = info
        return info
    }

    func copyNV12Planes(from imageBuffer: CVPixelBuffer, destination img: UnsafeMutablePointer<vpx_image_t>) throws {
        let lockFlags = CVPixelBufferLockFlags.readOnly
        let lockResult = CVPixelBufferLockBaseAddress(imageBuffer, lockFlags)
        guard lockResult == kCVReturnSuccess else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, lockFlags) }

        guard CVPixelBufferGetPlaneCount(imageBuffer) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1)?.assumingMemoryBound(to: UInt8.self)
        else {
            throw VideoEncoderError.invalidSampleBuffer
        }

        let yStride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1)
        let yWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
        let uvWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 1)

        // vpx_image_t exposes C fixed-size arrays as Swift tuples: planes[4] → (.0 ... .3).
        guard let yDest = img.pointee.planes.0,
              let uDest = img.pointee.planes.1,
              let vDest = img.pointee.planes.2
        else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        let yDestStride = Int(img.pointee.stride.0)
        let uDestStride = Int(img.pointee.stride.1)
        let vDestStride = Int(img.pointee.stride.2)

        // Y plane — copy row by row (strides on either side may be padded).
        let copyYCols = min(yWidth, Int(sourceWidth))
        let copyYRows = min(yHeight, Int(sourceHeight))
        for row in 0..<copyYRows {
            let src = yBase.advanced(by: row * yStride)
            let dst = yDest.advanced(by: row * yDestStride)
            memcpy(dst, src, copyYCols)
        }

        // UV plane — de-interleave [U V U V ...] into two planar U / V buffers.
        // VP8 I420 wants half-resolution chroma planes.
        let copyUVCols = min(uvWidth, Int(sourceWidth / 2))
        let copyUVRows = min(uvHeight, Int(sourceHeight / 2))
        for row in 0..<copyUVRows {
            let srcRow = uvBase.advanced(by: row * uvStride)
            let uDstRow = uDest.advanced(by: row * uDestStride)
            let vDstRow = vDest.advanced(by: row * vDestStride)
            var col = 0
            while col < copyUVCols {
                uDstRow[col] = srcRow[col * 2]
                vDstRow[col] = srcRow[col * 2 + 1]
                col += 1
            }
        }
    }
}

// MARK: - Output collection

private extension VPXVideoEncoder {
    func drainEncodedPackets() {
        guard let ctx = encoderCtx else { return }
        var iter: vpx_codec_iter_t? = nil
        while let pkt = vpx_codec_get_cx_data(ctx, &iter) {
            guard pkt.pointee.kind == VPX_CODEC_CX_FRAME_PKT else { continue }

            let frame = pkt.pointee.data.frame
            guard let buf = frame.buf else { continue }
            let size = frame.sz

            guard size <= Int(UInt32.max) else {
                continuation.yield(.errorOccurred(VideoEncoderError.payloadTooLarge(size)))
                continue
            }

            let frameID: UInt64
            if pendingFrameIDs.isEmpty {
                // Should not happen in real-time mode, but fail soft.
                logger.warning("received VPX packet without pending frameID")
                frameID = 0
            } else {
                frameID = pendingFrameIDs.removeFirst()
            }

            let data = Data(bytes: buf, count: size)

            let isKeyframe = (frame.flags & vpxFrameIsKeyFlag) != 0
            let flags: ProjectionDataFlags = isKeyframe ? .isKeyframe : []

            // libvpx round-trips the PTS we handed it in `vpx_codec_encode`,
            // which is already in microseconds because `g_timebase = 1 µs`.
            let header = FrameDataHeader(
                frameID: frameID,
                frameLength: UInt32(size),
                presentationTimestamp: UInt64(max(frame.pts, 0)),
                flags: flags
            )

            let encodedFrame = EncodedFrame(
                header: header,
                data: data,
                formatDescription: nil
            )

            continuation.yield(.frameEncoded(encodedFrame))
        }
    }
}

// MARK: - Helpers

private extension VPXVideoEncoder {
    /// VPX_DL_REALTIME is a preprocessor macro (`1ul`), not available in Swift.
    var vpxRealtimeDeadline: UInt { 1 }

    /// VPX_EFLAG_FORCE_KF is a preprocessor macro (`1 << 0`).
    var vpxForceKeyframeFlag: vpx_enc_frame_flags_t { 1 }

    /// VPX_FRAME_IS_KEY is a preprocessor macro (`0x1u`).
    var vpxFrameIsKeyFlag: vpx_codec_frame_flags_t { 0x1 }

    func microseconds(from time: CMTime) -> UInt64 {
        guard time.isValid, time.timescale != 0 else { return 0 }
        let scaled = CMTimeConvertScale(time, timescale: 1_000_000, method: .default)
        if scaled.value < 0 {
            return 0
        }
        return UInt64(scaled.value)
    }
}
