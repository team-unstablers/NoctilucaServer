//
//  ProjectionCanvasRenderer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/27/26.
//

import MetalKit

/// Metal 캔버스 텍스처를 화면에 직접 렌더링하는 MTKView 델리게이트.
///
/// MetalTileCompositor가 타일을 블리팅한 캔버스 텍스처를 fullscreen quad로 그려서
/// CVPixelBuffer → CMSampleBuffer → AVSampleBufferDisplayLayer 경유를 제거한다.
///
/// Rule G 확장: 미디어 파이프라인 class 예외 (문서 Section 9.5.2 참조).
/// canvasTexture 는 ProjectionSession actor 가 순차적으로 갱신하고, draw(in:) 은
/// MTKView delegate 로 main thread 에서만 호출되므로 실제 race 는 없다.
final class ProjectionCanvasRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState

    /// MetalTileCompositor의 캔버스 텍스처 참조.
    /// 외부에서 설정하며, draw() 시 이 텍스처를 fullscreen quad로 렌더링한다.
    var canvasTexture: MTLTexture?

    private weak var boundView: MTKView?

    init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw ProjectionCanvasRendererError.commandQueueCreationFailed
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            throw ProjectionCanvasRendererError.libraryNotFound
        }

        // Render Pipeline
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "projection_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "projection_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        // Sampler (linear filtering으로 리사이즈 시 부드럽게)
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .notMipmapped
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge

        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw ProjectionCanvasRendererError.samplerCreationFailed
        }
        self.samplerState = sampler

        super.init()
    }

    func bind(to view: MTKView) {
        self.boundView = view
    }

    /// 캔버스가 업데이트되었음을 알린다. MTKView에 다시 그리기를 요청한다.
    func setNeedsDisplay() {
        guard let view = boundView else { return }
        DispatchQueue.main.async {
            view.setNeedsDisplay(view.bounds)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // drawable 크기 변경 시 다시 그리기
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        guard let canvasTexture,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(canvasTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        // vertex shader가 vertex_id로 fullscreen quad를 생성하므로 vertex buffer 불필요
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

enum ProjectionCanvasRendererError: LocalizedError {
    case commandQueueCreationFailed
    case libraryNotFound
    case samplerCreationFailed

    var errorDescription: String? {
        switch self {
        case .commandQueueCreationFailed: return "Failed to create Metal command queue"
        case .libraryNotFound: return "Metal default library not found"
        case .samplerCreationFailed: return "Failed to create Metal sampler state"
        }
    }
}
