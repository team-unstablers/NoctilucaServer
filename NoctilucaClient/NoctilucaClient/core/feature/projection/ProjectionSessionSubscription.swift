//
//  ProjectionSessionSubscription.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

import AVFoundation
import Metal

import SiriusKitClient

/// 프로젝션 세션에 대한 구독 객체.
///
/// VT 코덱(H.264/H.265) 사용 시에는 `metalVideoRenderer`를 통해
/// CVPixelBuffer를 Metal 셰이더로 직접 렌더링한다.
/// 타일 코덱(WebP/ZRLE/MJPG) 사용 시에는 `canvasRenderer`를 통해
/// Metal 캔버스 텍스처를 직접 렌더링한다.
///
/// Metal이 불가능한 환경(시뮬레이터 등)에서는 `displayLayer`를 통한
/// AVSampleBufferDisplayLayer fallback 경로를 사용한다.
class ProjectionSessionSubscription {
    private static let logger = NoctilucaLogger(category: "ProjectionSessionSubscription")

    /// AVSampleBufferDisplayLayer fallback (Metal 불가 시)
    let displayLayer = AVSampleBufferDisplayLayer()
    let session: ProjectionSession
    private let ticket: RemoteSession.SessionReferenceTicket

    /// VT 코덱용 Metal 비디오 렌더러.
    /// Metal이 가용하고 VT 코덱(H.264/H.265)일 때 자동으로 생성된다.
    private(set) var metalVideoRenderer: MetalVideoRenderer?

    /// 타일 코덱용 Metal 캔버스 렌더러.
    /// 세션의 코덱이 타일 기반이면 자동으로 생성된다.
    private(set) var canvasRenderer: ProjectionCanvasRenderer?

    var displayID: Int { session.displayID }

    /// 현재 세션이 Metal 캔버스 직접 렌더링을 사용하는지 여부
    var useDirectCanvasRendering: Bool {
        canvasRenderer != nil
    }

    /// 현재 세션이 Metal 비디오 렌더러를 사용하는지 여부
    var useMetalVideoRendering: Bool {
        metalVideoRenderer != nil
    }

    private let rendererImplementation: AppSettings.RendererImplementation
    private var isInvalidated = false

    init(session: ProjectionSession, ticket: RemoteSession.SessionReferenceTicket, rendererImplementation: AppSettings.RendererImplementation = .avSampleBufferDisplayLayer) {
        self.session = session
        self.ticket = ticket
        self.rendererImplementation = rendererImplementation

        setupVTCodecRenderer()
    }

    /// 설정에 따라 VT 코덱용 렌더러를 초기화한다.
    private func setupVTCodecRenderer() {
        if rendererImplementation == .nocMetalVideoRenderer, tryCreateMetalVideoRenderer() {
            Self.logger.info("Using MetalVideoRenderer for VT codec rendering")
        } else {
            session.registerDisplayLayer(displayLayer)
            if rendererImplementation == .nocMetalVideoRenderer {
                Self.logger.warning("MetalVideoRenderer creation failed, falling back to AVSampleBufferDisplayLayer")
            } else {
                Self.logger.info("Using AVSampleBufferDisplayLayer for VT codec rendering")
            }
        }
    }

    /// 명시적 리소스 해제. 호출 즉시 display layer/renderer를 해제하고 ticket을 반환한다.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        session.unregisterDisplayLayer(displayLayer)
        if let renderer = metalVideoRenderer {
            session.unregisterMetalVideoRenderer(renderer)
            metalVideoRenderer = nil
        }
        if let renderer = canvasRenderer {
            session.unregisterCanvasRenderer(renderer)
            canvasRenderer = nil
        }
        ticket.release()
    }

    deinit {
        // safety-net: invalidate() 미호출 시에도 리소스 누수 방지
        if !isInvalidated {
            session.unregisterDisplayLayer(displayLayer)
            if let renderer = metalVideoRenderer {
                session.unregisterMetalVideoRenderer(renderer)
            }
            if let renderer = canvasRenderer {
                session.unregisterCanvasRenderer(renderer)
            }
            // ticket.deinit이 release를 처리
        }
    }

    /// 코덱 재설정 시 호출: 렌더링 경로를 업데이트한다.
    func updateRenderingPath(isTiledCodec: Bool) {
        if isTiledCodec {
            // 타일 코덱: Metal 비디오 렌더러 제거, 캔버스 렌더러 생성
            removeMetalVideoRenderer()
            session.unregisterDisplayLayer(displayLayer)
            if canvasRenderer == nil {
                tryCreateCanvasRenderer()
            }
        } else {
            // VT 코덱: 캔버스 렌더러 제거, 설정에 따라 렌더러 선택
            removeCanvasRenderer()
            if rendererImplementation == .nocMetalVideoRenderer && metalVideoRenderer == nil {
                if !tryCreateMetalVideoRenderer() {
                    session.registerDisplayLayer(displayLayer)
                }
            } else if rendererImplementation == .avSampleBufferDisplayLayer {
                removeMetalVideoRenderer()
                session.registerDisplayLayer(displayLayer)
            }
        }
    }

    // MARK: - Metal Video Renderer

    @discardableResult
    private func tryCreateMetalVideoRenderer() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logger.warning("Metal not available, cannot create video renderer")
            return false
        }
        do {
            let renderer = try MetalVideoRenderer(device: device)
            metalVideoRenderer = renderer
            session.registerMetalVideoRenderer(renderer)
            return true
        } catch {
            Self.logger.error("Failed to create MetalVideoRenderer: \(error.localizedDescription)")
            return false
        }
    }

    private func removeMetalVideoRenderer() {
        if let renderer = metalVideoRenderer {
            session.unregisterMetalVideoRenderer(renderer)
            metalVideoRenderer = nil
        }
    }

    // MARK: - Canvas Renderer

    private func tryCreateCanvasRenderer() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logger.warning("Metal not available, cannot create canvas renderer")
            return
        }
        do {
            let renderer = try ProjectionCanvasRenderer(device: device)
            canvasRenderer = renderer
            session.registerCanvasRenderer(renderer)
        } catch {
            Self.logger.error("Failed to create canvas renderer: \(error.localizedDescription)")
        }
    }

    private func removeCanvasRenderer() {
        if let renderer = canvasRenderer {
            session.unregisterCanvasRenderer(renderer)
            canvasRenderer = nil
        }
    }
}
