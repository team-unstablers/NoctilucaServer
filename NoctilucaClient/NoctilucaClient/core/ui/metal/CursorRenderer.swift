import MetalKit
import CoreGraphics
import Combine

class CursorRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?

    // 현재 커서 상태 캐싱
    private var currentTexture: MTLTexture?
    private var currentPosition: CGPoint = .zero
    private var currentHotspot: CGPoint = .zero
    private var currentCursorSize: CGSize = .zero
    private var currentSourceSize: CGSize = .zero
    private var viewportSize: CGSize = .zero

    // 커서 크기 배율 (1.0 = 원본 크기)
    private(set) var cursorScale: CGFloat = 1.0

    // displayID 기반 visibility (SwiftUI .opacity() 대체)
    private var targetDisplayID: Int = -1
    private var currentDisplayID: Int? = nil

    private let textureLoader: MTKTextureLoader

    // Combine 기반 직접 구독 (SwiftUI 뷰 업데이트 파이프라인 우회)
    private weak var boundView: MTKView?
    private weak var observedState: RemoteSession.CursorState?
    private var stateSubscription: AnyCancellable?

    // Quad Vertices (x, y, u, v) - (0,0) ~ (1,1) 범위의 사각형
    private let vertexData: [Float] = [
        0.0, 0.0, 0.0, 0.0, // Top-Left
        0.0, 1.0, 0.0, 1.0, // Bottom-Left
        1.0, 0.0, 1.0, 0.0, // Top-Right
        1.0, 1.0, 1.0, 1.0  // Bottom-Right
    ]

    // 이전 커서 이미지 ID (중복 로드 방지용)
    private var lastCursorImageID: UInt64? = nil

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)

        super.init()

        setupPipeline()
        setupBuffers()
        setupSampler()
    }
    
    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cursor_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cursor_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // 투명도 블렌딩 설정
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupBuffers() {
        let size = vertexData.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: size, options: [])
    }

    private func setupSampler() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .nearest
        descriptor.magFilter = .nearest
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: descriptor)
    }
    
    // MARK: - Cursor Scale

    func setCursorScale(_ scale: CGFloat) {
        let clamped = max(0.25, min(scale, 4.0))
        guard cursorScale != clamped else { return }
        cursorScale = clamped
        if let view = boundView {
            view.setNeedsDisplay(view.bounds)
        }
    }

    // MARK: - Combine Binding (SwiftUI 우회)

    /// CursorState를 Combine으로 직접 구독하여 SwiftUI 뷰 업데이트 파이프라인을 우회합니다.
    func bind(to view: MTKView, cursorState: RemoteSession.CursorState, sourceSize: CGSize, targetDisplayID: Int) {
        self.boundView = view
        self.observedState = cursorState

        stateSubscription?.cancel()
        stateSubscription = cursorState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncCursorState()
            }

        // 초기 동기화
        updateCursorState(cursorState, sourceSize: sourceSize, targetDisplayID: targetDisplayID, in: view)
    }

    /// sourceSize/targetDisplayID 변경 시 호출 (SwiftUI updateNSView/updateUIView에서 사용)
    func updateSourceParameters(sourceSize: CGSize, targetDisplayID: Int) {
        guard let view = boundView, let state = observedState else { return }
        updateCursorState(state, sourceSize: sourceSize, targetDisplayID: targetDisplayID, in: view)
    }

    private func syncCursorState() {
        guard let view = boundView, let state = observedState else { return }
        updateCursorState(state, sourceSize: currentSourceSize, targetDisplayID: targetDisplayID, in: view)
    }

    // MARK: - Update Logic (Event Driven)

    private func updateCursorState(_ state: RemoteSession.CursorState, sourceSize: CGSize, targetDisplayID: Int, in view: MTKView) {
        var needsRedraw = false

        // targetDisplayID 변경 감지
        if self.targetDisplayID != targetDisplayID {
            self.targetDisplayID = targetDisplayID
            needsRedraw = true
        }

        // displayID 변경 감지 (커서가 다른 디스플레이로 이동)
        if self.currentDisplayID != state.displayID {
            self.currentDisplayID = state.displayID
            needsRedraw = true
        }

        // 위치 변경 감지
        if self.currentPosition != state.position {
            self.currentPosition = state.position
            needsRedraw = true
        }

        // 이미지 변경 감지
        if let image = state.image {
            if self.lastCursorImageID != image.id {
                 loadCursorImage(image)
                 self.lastCursorImageID = image.id
                 needsRedraw = true
            }
        } else {
            if self.currentTexture != nil {
                self.currentTexture = nil
                self.lastCursorImageID = nil
                needsRedraw = true
            }
        }

        if self.currentSourceSize != sourceSize {
            self.currentSourceSize = sourceSize
            needsRedraw = true
        }

        // 변경사항이 있을 때만 그리기 요청
        if needsRedraw {
            view.setNeedsDisplay(view.bounds)
        }
    }
    
    private func loadCursorImage(_ cursorImage: RemoteSession.CursorImage) {
        do {
            self.currentTexture = try textureLoader.newTexture(cgImage: cursorImage.image, options: nil)
            self.currentCursorSize = cursorImage.size
            self.currentHotspot = cursorImage.hotspot
        } catch {
            print("Failed to load cursor texture: \(error)")
        }
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.viewportSize = size
        view.setNeedsDisplay(view.bounds)
    }
    
    func draw(in view: MTKView) {
        // displayID가 일치하지 않으면 투명하게 클리어만 수행
        let isVisible = currentDisplayID == targetDisplayID

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            return
        }

        guard isVisible,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer,
              let texture = currentTexture,
              let samplerState = samplerState else {
            // 커서가 보이지 않거나 텍스처가 없는 경우: 투명하게 클리어
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            if let commandBuffer = commandQueue.makeCommandBuffer(),
               let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            return
        }

        if viewportSize != view.drawableSize {
            viewportSize = view.drawableSize
        }
        
        // 배경 투명 처리
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let resolvedSourceSize = (currentSourceSize.width > 0 && currentSourceSize.height > 0) ? currentSourceSize : viewportSize
        let scaleX = resolvedSourceSize.width > 0 ? viewportSize.width / resolvedSourceSize.width : 1.0
        let scaleY = resolvedSourceSize.height > 0 ? viewportSize.height / resolvedSourceSize.height : 1.0

        let scaledPosition = CGPoint(
            x: currentPosition.x * scaleX,
            y: currentPosition.y * scaleY
        )
        let scaledSize = CGSize(
            width: currentCursorSize.width * scaleX * cursorScale,
            height: currentCursorSize.height * scaleY * cursorScale
        )
        let scaledHotspot = CGPoint(
            x: currentHotspot.x * scaleX * cursorScale,
            y: currentHotspot.y * scaleY * cursorScale
        )

        var uniforms = CursorUniforms(
            cursorPosition: SIMD2<Float>(Float(scaledPosition.x), Float(scaledPosition.y)),
            cursorSize: SIMD2<Float>(Float(scaledSize.width), Float(scaledSize.height)),
            hotspot: SIMD2<Float>(Float(scaledHotspot.x), Float(scaledHotspot.y)),
            viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
        )
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CursorUniforms>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct CursorUniforms {
    var cursorPosition: SIMD2<Float>
    var cursorSize: SIMD2<Float>
    var hotspot: SIMD2<Float>
    var viewportSize: SIMD2<Float>
}
