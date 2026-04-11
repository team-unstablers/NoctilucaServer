//
//  MetalVideoRenderer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/22/26.
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

import SiriusKitClient

/// Metal 기반 VT 코덱(H.264/H.265) 비디오 렌더러.
///
/// VTDecompressionSession이 출력한 CVPixelBuffer를 CVMetalTextureCache로
/// zero-copy Metal 텍스처로 변환하고, YUV→RGB 포맷 변환/HDR 톤매핑/CAS
/// 후처리를 적용하여 CAMetalLayer에 렌더링한다.
///
/// ## 스레드 모델
/// - `present(_:)`: 디코더 콜백 큐에서 호출 (thread-safe)
/// - `draw(in:)`: Main thread (MTKView delegate)
///
/// Rule G 확장: 미디어 파이프라인 class 예외 (문서 Section 9.5.2 참조).
/// 내부 Metal command queue의 순서 보장과 lastPixelBuffer용 lock 으로
/// thread-safety 확보.
final class MetalVideoRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private static let logger = NoctilucaLogger(category: "MetalVideoRenderer")

    // MARK: - GPU Resources

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache!

    // MARK: - Pipelines

    private var formatPipeline: MTLRenderPipelineState!
    private var formatHDRPipeline: MTLRenderPipelineState!
    private var tonemapPipeline: MTLRenderPipelineState!
    private var casPipeline: MTLRenderPipelineState!
    private var samplerState: MTLSamplerState!

    // MARK: - Intermediate Render Targets

    /// HDR 톤매핑용 중간 텍스처 (RGBA16Float)
    private var intermediateTexture: MTLTexture?
    /// CAS 입력용 중간 텍스처 (BGRA8Unorm)
    private var sharpenTexture: MTLTexture?

    private var lastFrameWidth: Int = 0
    private var lastFrameHeight: Int = 0

    // MARK: - Frame State (thread-safe)

    private let frameLock = NSLock()
    private var pendingPixelBuffer: CVPixelBuffer?

    // MARK: - Codec Metadata

    private(set) var colorSpace: VideoColorSpace = .bt709
    private var colorRange: CodecOptionValue = .kColorRangeLimited
    private var is10Bit: Bool = false

    /// 현재 활성 포맷 유니폼
    private var formatUniforms = FormatUniforms()
    /// 현재 활성 톤매핑 유니폼
    private var tonemapUniforms = TonemapUniforms()

    // MARK: - Configuration

    /// CAS 활성화 여부
    var casEnabled: Bool = false {
        didSet {
            guard casEnabled != oldValue else { return }
            invalidateIntermediateTextures()
            requestRedraw()
        }
    }
    /// CAS 선명도 (0.0~1.0)
    var casSharpness: Float = 0.5 {
        didSet { requestRedraw() }
    }
    /// HDR 스트림에 대한 셰이더 톤매핑 fallback 활성화 여부.
    /// macOS 26+/iOS 26+에서는 OS 위임이 우선이며, 이전 OS에서만 활성화된다.
    private(set) var useShaderTonemap: Bool = false

    // MARK: - View Binding

    private weak var boundView: MTKView?

    // MARK: - Lifecycle

    init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw MetalVideoRendererError.commandQueueCreationFailed
        }
        self.commandQueue = queue

        super.init()

        try setupTextureCache()
        try setupPipelines()
        setupSampler()
    }

    // MARK: - Setup

    private func setupTextureCache() throws {
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard result == kCVReturnSuccess, let cache else {
            throw MetalVideoRendererError.textureCacheCreationFailed
        }
        self.textureCache = cache
    }

    private func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw MetalVideoRendererError.libraryNotFound
        }

        guard let vertexFn = library.makeFunction(name: "video_format_vertex"),
              let formatFn = library.makeFunction(name: "format_biplanar"),
              let formatHDRFn = library.makeFunction(name: "format_biplanar_hdr"),
              let tonemapFn = library.makeFunction(name: "tonemap_fragment"),
              let casFn = library.makeFunction(name: "cas_fragment")
        else {
            throw MetalVideoRendererError.shaderFunctionNotFound
        }

        // Format pipeline (SDR 출력)
        let formatDesc = MTLRenderPipelineDescriptor()
        formatDesc.vertexFunction = vertexFn
        formatDesc.fragmentFunction = formatFn
        formatDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.formatPipeline = try device.makeRenderPipelineState(descriptor: formatDesc)

        // Format HDR pipeline (RGBA16Float 중간 텍스처 출력)
        let formatHDRDesc = MTLRenderPipelineDescriptor()
        formatHDRDesc.vertexFunction = vertexFn
        formatHDRDesc.fragmentFunction = formatHDRFn
        formatHDRDesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.formatHDRPipeline = try device.makeRenderPipelineState(descriptor: formatHDRDesc)

        // Tonemap pipeline (SDR 출력)
        let tonemapDesc = MTLRenderPipelineDescriptor()
        tonemapDesc.vertexFunction = vertexFn
        tonemapDesc.fragmentFunction = tonemapFn
        tonemapDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.tonemapPipeline = try device.makeRenderPipelineState(descriptor: tonemapDesc)

        // CAS pipeline (SDR 출력)
        let casDesc = MTLRenderPipelineDescriptor()
        casDesc.vertexFunction = vertexFn
        casDesc.fragmentFunction = casFn
        casDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.casPipeline = try device.makeRenderPipelineState(descriptor: casDesc)
    }

    private func setupSampler() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .notMipmapped
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: desc)
    }

    // MARK: - Public API

    /// MTKView에 바인딩한다.
    func bind(to view: MTKView) {
        self.boundView = view
    }

    /// 디코딩된 프레임을 제출한다.
    /// VTVideoDecoder의 콜백 큐에서 호출되며, thread-safe하다.
    func present(_ pixelBuffer: CVPixelBuffer) {
        frameLock.lock()
        pendingPixelBuffer = pixelBuffer
        frameLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.boundView else { return }
            view.setNeedsDisplay(view.bounds)
        }
    }

    /// 코덱 메타데이터를 업데이트한다. prepare(codec:) 시점에서 호출된다.
    func updateCodecMetadata(codec: SiriusKitClient.Codec) {
        colorSpace = VideoColorSpace(from: codec)
        colorRange = codec.option(.colorRange) ?? .kColorRangeLimited
        is10Bit = codec.supports10Bit

        formatUniforms = YUVColorMatrix.buildFormatUniforms(
            colorSpace: colorSpace,
            colorRange: colorRange,
            is10Bit: is10Bit
        )
        tonemapUniforms = YUVColorMatrix.buildTonemapUniforms(
            colorSpace: colorSpace
        )

        updateShaderTonemapState()
    }

    private func updateShaderTonemapState() {
        if colorSpace.isHDR {
            if #available(macOS 26.0, iOS 26.0, *) {
                // OS가 톤매핑을 처리 → 셰이더 톤매핑 비활성화
                useShaderTonemap = false
            } else {
                useShaderTonemap = true
            }
        } else {
            useShaderTonemap = false
        }
    }

    // MARK: - Metal Texture Creation

    private func createMetalTextures(from pixelBuffer: CVPixelBuffer) -> (yTexture: MTLTexture, uvTexture: MTLTexture)? {
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        guard planeCount >= 2 else {
            Self.logger.error("CVPixelBuffer has \(planeCount) planes, expected >= 2")
            return nil
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard let metalFormat = MetalVideoPixelFormat(cvPixelFormat: pixelFormat) else {
            Self.logger.error("Unsupported CVPixelBuffer format: \(pixelFormat)")
            return nil
        }

        // Plane 0: Y
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        var yTextureRef: CVMetalTexture?
        let yResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            metalFormat.yPlaneFormat, yWidth, yHeight, 0, &yTextureRef
        )

        // Plane 1: UV (CbCr)
        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        var uvTextureRef: CVMetalTexture?
        let uvResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            metalFormat.uvPlaneFormat, uvWidth, uvHeight, 1, &uvTextureRef
        )

        guard yResult == kCVReturnSuccess, uvResult == kCVReturnSuccess,
              let yRef = yTextureRef, let uvRef = uvTextureRef,
              let yTex = CVMetalTextureGetTexture(yRef),
              let uvTex = CVMetalTextureGetTexture(uvRef)
        else {
            Self.logger.error("Failed to create Metal textures from CVPixelBuffer (Y: \(yResult), UV: \(uvResult))")
            return nil
        }

        return (yTex, uvTex)
    }

    // MARK: - Intermediate Texture Management

    /// 설정 변경 시 중간 텍스처를 강제 재생성하기 위한 플래그
    private var intermediateTexturesDirty: Bool = true

    private func invalidateIntermediateTextures() {
        intermediateTexturesDirty = true
    }

    private func requestRedraw() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.boundView else { return }
            view.setNeedsDisplay(view.bounds)
        }
    }

    private func ensureIntermediateTextures(width: Int, height: Int) {
        let sizeChanged = width != lastFrameWidth || height != lastFrameHeight
        guard sizeChanged || intermediateTexturesDirty else { return }

        lastFrameWidth = width
        lastFrameHeight = height
        intermediateTexturesDirty = false

        // HDR intermediate (RGBA16Float)
        if useShaderTonemap {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false
            )
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            intermediateTexture = device.makeTexture(descriptor: desc)
        } else {
            intermediateTexture = nil
        }

        // CAS sharpen texture
        if casEnabled {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
            )
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            sharpenTexture = device.makeTexture(descriptor: desc)
        } else {
            sharpenTexture = nil
        }
    }

    // MARK: - Render Pass Helpers

    private func encodeFormatPass(
        encoder: MTLRenderCommandEncoder,
        pipeline: MTLRenderPipelineState,
        yTexture: MTLTexture,
        uvTexture: MTLTexture
    ) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uvTexture, index: 1)
        encoder.setFragmentBytes(&formatUniforms, length: MemoryLayout<FormatUniforms>.size, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeTonemapPass(
        encoder: MTLRenderCommandEncoder,
        sourceTexture: MTLTexture
    ) {
        encoder.setRenderPipelineState(tonemapPipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&tonemapUniforms, length: MemoryLayout<TonemapUniforms>.size, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeCASPass(
        encoder: MTLRenderCommandEncoder,
        sourceTexture: MTLTexture
    ) {
        // texelSize는 샘플링 대상(source) 텍스처 기준이어야 한다
        var casUniforms = CASUniforms(
            texelSize: SIMD2(1.0 / Float(sourceTexture.width), 1.0 / Float(sourceTexture.height)),
            sharpness: casSharpness,
            _pad: 0
        )
        encoder.setRenderPipelineState(casPipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&casUniforms, length: MemoryLayout<CASUniforms>.size, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeRenderPassDescriptor(for texture: MTLTexture) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        return desc
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // drawable 크기 변경 시 다시 그리기
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        // 프레임 교환
        frameLock.lock()
        let pixelBuffer = pendingPixelBuffer
        pendingPixelBuffer = nil
        frameLock.unlock()

        guard let pixelBuffer else { return }

        // CVPixelBuffer의 전달 함수 어태치먼트로 per-frame HDR 정밀 감지
        if colorSpace.isHDR {
            let detected = VideoColorSpace.detectFromPixelBuffer(pixelBuffer)
            if detected != colorSpace {
                colorSpace = detected
                tonemapUniforms = YUVColorMatrix.buildTonemapUniforms(colorSpace: colorSpace)
            }
        }

        // Metal 텍스처 생성 (zero-copy)
        guard let (yTexture, uvTexture) = createMetalTextures(from: pixelBuffer) else { return }

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
        ensureIntermediateTextures(width: frameWidth, height: frameHeight)

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let drawableTexture = drawable.texture
        let outputWidth = drawableTexture.width
        let outputHeight = drawableTexture.height

        // 렌더 패스 결정 및 실행
        if useShaderTonemap {
            // HDR 셰이더 톤매핑 경로
            renderHDRPath(
                commandBuffer: commandBuffer,
                yTexture: yTexture, uvTexture: uvTexture,
                drawableTexture: drawableTexture,
                drawableDescriptor: view.currentRenderPassDescriptor!,
                outputWidth: outputWidth, outputHeight: outputHeight
            )
        } else if casEnabled {
            // SDR + CAS 경로
            renderSDRCASPath(
                commandBuffer: commandBuffer,
                yTexture: yTexture, uvTexture: uvTexture,
                drawableTexture: drawableTexture,
                drawableDescriptor: view.currentRenderPassDescriptor!,
                outputWidth: outputWidth, outputHeight: outputHeight
            )
        } else {
            // SDR 1-pass 경로
            renderSDRPath(
                commandBuffer: commandBuffer,
                yTexture: yTexture, uvTexture: uvTexture,
                drawableDescriptor: view.currentRenderPassDescriptor!
            )
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Render Paths

    /// SDR 1-pass: format → drawable
    private func renderSDRPath(
        commandBuffer: MTLCommandBuffer,
        yTexture: MTLTexture, uvTexture: MTLTexture,
        drawableDescriptor: MTLRenderPassDescriptor
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDescriptor) else { return }
        encodeFormatPass(encoder: encoder, pipeline: formatPipeline, yTexture: yTexture, uvTexture: uvTexture)
    }

    /// SDR + CAS 2-pass: format → sharpenRT → CAS → drawable
    private func renderSDRCASPath(
        commandBuffer: MTLCommandBuffer,
        yTexture: MTLTexture, uvTexture: MTLTexture,
        drawableTexture: MTLTexture,
        drawableDescriptor: MTLRenderPassDescriptor,
        outputWidth: Int, outputHeight: Int
    ) {
        guard let sharpenTex = sharpenTexture else {
            // fallback to 1-pass
            renderSDRPath(commandBuffer: commandBuffer, yTexture: yTexture, uvTexture: uvTexture, drawableDescriptor: drawableDescriptor)
            return
        }

        // Pass 1: format → sharpenRT
        let sharpenRPD = makeRenderPassDescriptor(for: sharpenTex)
        guard let encoder1 = commandBuffer.makeRenderCommandEncoder(descriptor: sharpenRPD) else { return }
        encodeFormatPass(encoder: encoder1, pipeline: formatPipeline, yTexture: yTexture, uvTexture: uvTexture)

        // Pass 2: CAS → drawable
        guard let encoder2 = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDescriptor) else { return }
        encodeCASPass(encoder: encoder2, sourceTexture: sharpenTex)
    }

    /// HDR 톤매핑 경로 (2~3 pass)
    private func renderHDRPath(
        commandBuffer: MTLCommandBuffer,
        yTexture: MTLTexture, uvTexture: MTLTexture,
        drawableTexture: MTLTexture,
        drawableDescriptor: MTLRenderPassDescriptor,
        outputWidth: Int, outputHeight: Int
    ) {
        guard let intermediateTex = intermediateTexture else {
            // fallback
            renderSDRPath(commandBuffer: commandBuffer, yTexture: yTexture, uvTexture: uvTexture, drawableDescriptor: drawableDescriptor)
            return
        }

        // Pass 1: format (HDR) → intermediateRT (RGBA16F)
        let intermediateRPD = makeRenderPassDescriptor(for: intermediateTex)
        guard let encoder1 = commandBuffer.makeRenderCommandEncoder(descriptor: intermediateRPD) else { return }
        encodeFormatPass(encoder: encoder1, pipeline: formatHDRPipeline, yTexture: yTexture, uvTexture: uvTexture)

        if casEnabled, let sharpenTex = sharpenTexture {
            // Pass 2: tonemap → sharpenRT
            let sharpenRPD = makeRenderPassDescriptor(for: sharpenTex)
            guard let encoder2 = commandBuffer.makeRenderCommandEncoder(descriptor: sharpenRPD) else { return }
            encodeTonemapPass(encoder: encoder2, sourceTexture: intermediateTex)

            // Pass 3: CAS → drawable
            guard let encoder3 = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDescriptor) else { return }
            encodeCASPass(encoder: encoder3, sourceTexture: sharpenTex)
        } else {
            // Pass 2: tonemap → drawable
            guard let encoder2 = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDescriptor) else { return }
            encodeTonemapPass(encoder: encoder2, sourceTexture: intermediateTex)
        }
    }
}

// MARK: - Errors

enum MetalVideoRendererError: LocalizedError {
    case commandQueueCreationFailed
    case textureCacheCreationFailed
    case libraryNotFound
    case shaderFunctionNotFound

    var errorDescription: String? {
        switch self {
        case .commandQueueCreationFailed: return "Failed to create Metal command queue"
        case .textureCacheCreationFailed: return "Failed to create CVMetalTextureCache"
        case .libraryNotFound: return "Metal default library not found"
        case .shaderFunctionNotFound: return "Required Metal shader function not found"
        }
    }
}
