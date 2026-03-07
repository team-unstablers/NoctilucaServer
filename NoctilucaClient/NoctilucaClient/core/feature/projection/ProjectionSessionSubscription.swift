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
/// 각 구독자는 자신만의 `AVSampleBufferDisplayLayer`를 소유하며,
/// `ProjectionSession`은 디코딩된 프레임을 등록된 모든 레이어에 브로드캐스트한다.
///
/// 타일 코덱(WebP/ZRLE/MJPG) 사용 시에는 `canvasRenderer`를 통해
/// Metal 캔버스 텍스처를 직접 렌더링한다.
class ProjectionSessionSubscription {
    private static let logger = NoctilucaLogger(category: "ProjectionSessionSubscription")

    let displayLayer = AVSampleBufferDisplayLayer()
    let session: ProjectionSession
    private let ticket: RemoteSession.SessionReferenceTicket

    /// 타일 코덱용 Metal 캔버스 렌더러.
    /// 세션의 코덱이 타일 기반이면 자동으로 생성된다.
    private(set) var canvasRenderer: ProjectionCanvasRenderer?

    var sourceDescriptor: ProjectionSourceDescriptor { session.sourceDescriptor }

    /// 현재 세션이 Metal 캔버스 직접 렌더링을 사용하는지 여부
    var useDirectCanvasRendering: Bool {
        canvasRenderer != nil
    }

    private var isInvalidated = false

    init(session: ProjectionSession, ticket: RemoteSession.SessionReferenceTicket) {
        self.session = session
        self.ticket = ticket
        session.registerDisplayLayer(displayLayer)
    }

    /// 명시적 리소스 해제. 호출 즉시 display layer/renderer를 해제하고 ticket을 반환한다.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        session.unregisterDisplayLayer(displayLayer)
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
            if let renderer = canvasRenderer {
                session.unregisterCanvasRenderer(renderer)
            }
            // ticket.deinit이 release를 처리
        }
    }

    /// 코덱 재설정 시 호출: 렌더링 경로를 업데이트한다.
    func updateRenderingPath(isTiledCodec: Bool) {
        if isTiledCodec {
            if canvasRenderer == nil {
                tryCreateCanvasRenderer()
            }
        } else {
            // VT 코덱으로 전환: 렌더러 제거
            if let renderer = canvasRenderer {
                session.unregisterCanvasRenderer(renderer)
                canvasRenderer = nil
            }
        }
    }

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
}
