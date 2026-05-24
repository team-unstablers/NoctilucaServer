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
/// VT 코덱(H.264/H.265) 또는 VP8 사용 시 `metalVideoRenderer`를 통해
/// CVPixelBuffer를 Metal 셰이더로 직접 렌더링한다.
///
/// Metal이 불가능한 환경(시뮬레이터 등)에서는 `displayLayer`를 통한
/// AVSampleBufferDisplayLayer fallback 경로를 사용한다.
///
/// `ProjectionSession` 이 actor 로 승격되었으므로, 이 객체의 register/unregister
/// 호출은 모두 `Task { await session.xxx }` 패턴으로 actor 경계를 넘는다.
@MainActor
final class ProjectionSessionSubscription {
    private static let logger = NoctilucaLogger(category: "ProjectionSessionSubscription")

    /// AVSampleBufferDisplayLayer fallback (Metal 불가 시)
    let displayLayer = AVSampleBufferDisplayLayer()
    let session: ProjectionSession
    private let ticket: RemoteSession.SessionReferenceTicket

    /// 비디오 코덱용 Metal 비디오 렌더러.
    /// Metal이 가용할 때 자동으로 생성된다.
    private(set) var metalVideoRenderer: MetalVideoRenderer?

    var sourceDescriptor: ProjectionSourceDescriptor { session.sourceDescriptor }

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

        setupVideoRenderer()
    }

    /// 설정에 따라 비디오 렌더러를 초기화한다.
    private func setupVideoRenderer() {
        if rendererImplementation == .nocMetalVideoRenderer, tryCreateMetalVideoRenderer() {
            Self.logger.info("Using MetalVideoRenderer for video rendering")
        } else {
            let layer = displayLayer
            let session = session
            Task { await session.registerDisplayLayer(layer) }
            if rendererImplementation == .nocMetalVideoRenderer {
                Self.logger.warning("MetalVideoRenderer creation failed, falling back to AVSampleBufferDisplayLayer")
            } else {
                Self.logger.info("Using AVSampleBufferDisplayLayer for video rendering")
            }
        }
    }

    /// 명시적 리소스 해제. 호출 즉시 display layer/renderer를 해제하고 ticket을 반환한다.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        let layer = displayLayer
        let session = session
        let metalRenderer = metalVideoRenderer

        Task {
            await session.unregisterDisplayLayer(layer)
            if let metalRenderer {
                await session.unregisterMetalVideoRenderer(metalRenderer)
            }
        }
        metalVideoRenderer = nil
        ticket.release()
    }

    deinit {
        // safety-net: invalidate() 미호출 시에도 리소스 누수 방지
        // nonisolated context 이므로 MainActor-isolated 필드 직접 접근 불가.
        // 여기서는 ticket release 만으로 충분 (SessionReferenceTicket.deinit 이 처리).
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
            let session = session
            Task { await session.registerMetalVideoRenderer(renderer) }
            return true
        } catch {
            Self.logger.error("Failed to create MetalVideoRenderer: \(error.localizedDescription)")
            return false
        }
    }
}
