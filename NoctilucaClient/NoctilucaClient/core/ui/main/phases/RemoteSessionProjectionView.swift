//
//  MainWindowMainPhaseContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI
import Combine

import SiriusKitClient

#if os(macOS)
import AppKit
#endif

struct RemoteSessionProjectionView: View {
    static let logger = NoctilucaLogger(category: "RemoteSessionProjectionView")
    
    @EnvironmentObject
    private var settingsStore: SettingsStore
    
    @ObservedObject
    var remoteSession: RemoteSession
    
    var client: NoctilucaClient {
        remoteSession.client
    }
    
    @ObservedObject
    var projection: RemoteSession.Projection
    
    @ObservedObject
    var hidio: RemoteSession.HIDIO
    
    @Binding
    var sourceDescriptor: ProjectionSourceDescriptor

    var subscription: ProjectionSessionSubscription?

    var source: ProjectionSession? { subscription?.session }
    
    @State
    var sourceSize: CGSize = .zero

    @State
    private var projectionAspectRatio: CGFloat = 16.0 / 9.0
    @State
    private var lastPerformanceReport: ProjectionPerformanceReport?

    @State
    private var useCanvasRendering: Bool = false

#if os(iOS)
    @State private var shouldPresentKeyboard: Bool = false
    @StateObject private var uiKitKeyboard = HIDIOUIKitKeyboard()
    @StateObject private var zoomController = ProjectionZoomController()
    @StateObject private var keyboardObserver = KeyboardHeightObserver()
    @EnvironmentObject private var windowViewModel: SessionWindowViewModel
#endif

    private var currentScale: CGFloat {
#if os(iOS)
        zoomController.scale
#else
        1.0
#endif
    }

    private var currentOffset: CGSize {
#if os(iOS)
        zoomController.offset
#else
        .zero
#endif
    }
    
    /// 커서 렌더링용 소스 크기: 디스플레이의 포인트(point) 단위 bounds.
    /// HiDPI 캡처 시 codec sourceSize는 픽셀 단위지만 커서 좌표는 항상 포인트 단위이므로,
    /// 커서 좌표 매핑에는 디스플레이 bounds를 사용해야 정확하다.
    private var cursorSourceSize: CGSize {
        if case .displayID(let displayID) = sourceDescriptor,
           let layout = projection.channel.displayLayoutManager.displayLayouts[displayID] {
            return layout.bounds.cgRect.size
        }
        return sourceSize
    }

    private func syncSourceMetadata() {
        guard let source else { return }
        self.sourceSize = source.size
        if source.size.width > 0, source.size.height > 0 {
            self.projectionAspectRatio = source.size.width / source.size.height
        }
    }

    private func syncMouseScope() {
        let scope = sourceDescriptor.toCursorPositionScope()

#if os(macOS)
        if let mouse = hidio.session.currentMouse as? HIDIOAppKitPointer {
            mouse.scope = scope
        }
#endif
#if os(iOS)
        if let mouse = hidio.session.defaultSubMouse as? HIDIOUIKitMouse {
            mouse.scope = scope
        }
#endif
    }

    var body: some View {
        // TODO: preparingView unless(remoteSession.projection)
        GeometryReader { geometry in
            ZStack {
                ZStack(alignment: .topLeading) {
#if os(iOS)
                    Rectangle()
                        .fill(.black)
                        .frame(width: geometry.size.width, height: geometry.size.height + 10)
#endif
                    
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                    
                    if useCanvasRendering, let renderer = subscription?.canvasRenderer {
                        // Metal 캔버스 직접 렌더링 경로 (타일 코덱)
                        MetalProjectionView(renderer: renderer)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .offset(currentOffset)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .scaleEffect(currentScale)
                    } else if let displayLayer = subscription?.displayLayer {
                        // AVSampleBufferDisplayLayer 경로 (VT 코덱)
                        SampleBufferDisplayView(displayLayer: displayLayer)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .offset(currentOffset)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .scaleEffect(currentScale)
                    }
                    
                    // Metal Cursor Overlay
                    // ZStack 위에 투명하게 얹음.
                    // allowsHitTesting(false) 필수: 마우스 클릭이 아래 뷰(입력 캡처)로 전달되어야 함.
                    // displayID 기반 visibility는 CursorRenderer 내부에서 처리 (SwiftUI 업데이트 지연 방지)
                    if case .displayID(let displayID) = sourceDescriptor {
                        MetalCursorView(cursorState: projection.cursorState, sourceSize: cursorSourceSize, targetDisplayID: displayID, cursorScale: settingsStore.settings.input.cursorScale)
                            .offset(currentOffset)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                            .scaleEffect(currentScale)
                    }
                    
#if os(macOS)
                    if hidio.sessionMode == .shared,
                       let mouse = hidio.session.currentMouse as? HIDIOAppKitPointer
                    {
                        HIDIOAppKitMouseView(pointer: mouse)
                            .offset(currentOffset)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
#endif
#if os(iOS)
                    if let mouse = hidio.session.defaultSubMouse as? HIDIOUIKitMouse {
                        HIDIOUIKitMouseView(
                            mouse: mouse,
                            mode: $settingsStore.settings.input.touchInputMode,
                            trackpadMoveMultiplier: $settingsStore.settings.input.trackpadMoveMultiplier,
                            zoomMode: zoomController.mode,
                            contentRect: rect,
                            zoomScale: zoomController.scale,
                            zoomOffset: zoomController.offset,
                            onPinchChanged: { zoomController.handlePinchChanged(magnification: $0) },
                            onPinchEnded: { zoomController.handlePinchEnded() },
                            onFreeDragChanged: { zoomController.handleFreeDragChanged(translation: $0) },
                            onFreeDragEnded: { zoomController.handleFreeDragEnded() }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    HIDIOUIKitKeyboardInputHost(
                        client: remoteSession.client,
                        keyboard: uiKitKeyboard,
                        isPresented: $shouldPresentKeyboard
                    )
                    
                    if windowViewModel.isFullscreen {
                        // 전체 화면 모드: 반투명 오버레이 트리거 버튼
                        Button {
                            windowViewModel.showFullscreenOverlay()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        .background(.black.opacity(0.15), in: Circle())
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    } else {
                        /*
                        Button {
                            shouldPresentKeyboard.toggle()
                        } label: {
                            Image(systemName: shouldPresentKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                         */
                    }
#endif
                    
                    if settingsStore.settings.misc.showPerformanceOverlay {
                        PerformanceOverlay(
                            codec: source?.codec,
                            rtt: remoteSession.pingRTT ?? 0,
                            receivedFps: lastPerformanceReport?.receivedFrameCount ?? 0,
                            droppedFrames: lastPerformanceReport?.droppedFrameCount ?? 0,
                            avgDecodeMs: lastPerformanceReport?.averageDecodeTimeMs ?? 0,
                            dataRateKbps: source?.currentDataRateKbps ?? 0,
                            decoderType: source?.decoderTypeName ?? "N/A"
                        )
                        .padding(8)
                    }
                }
                .background(.background)
                .onAppear {
                    syncSourceMetadata()
                    syncMouseScope()
#if os(iOS)
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                    zoomController.mode = .defaultFor(settingsStore.settings.input.touchInputMode)
                    zoomController.updateGeometry(contentRect: rect, containerSize: geometry.size)
#endif
                }
                .onChange(of: source?.id) { _, _ in
                    syncSourceMetadata()
                }
#if os(iOS)
                .onChange(of: geometry.size) { _, newSize in
                    let rect = fittedProjectionRect(in: newSize, aspectRatio: projectionAspectRatio)
                    zoomController.updateGeometry(contentRect: rect, containerSize: newSize)
                }
                .onChange(of: projectionAspectRatio) { _, newRatio in
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: newRatio)
                    zoomController.updateGeometry(contentRect: rect, containerSize: geometry.size)
                }
#endif
                .onChange(of: sourceDescriptor) { _, _ in
                    syncMouseScope()
                }
#if os(iOS)
                .onReceive(projection.cursorState.$position) { newPosition in
                    let csSize = cursorSourceSize
                    guard csSize.width > 0, csSize.height > 0 else { return }
                    let normalized = CGPoint(
                        x: newPosition.x / csSize.width,
                        y: newPosition.y / csSize.height
                    )
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                    zoomController.updateViewportForCursor(
                        normalizedCursorPosition: normalized,
                        contentRect: rect,
                        containerSize: geometry.size
                    )
                }
#endif
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .if(subscription != nil) {
                    $0
                        .onReceive(source!.events) { event in
                            switch event {
                            case .sizeChanged(let size):
                                sourceSize = size
                                if size.width > 0, size.height > 0 {
                                    projectionAspectRatio = size.width / size.height
                                }
                            case .performanceReportEmitted(let report):
                                lastPerformanceReport = report
                            case .codecConfigured(let isTiledCodec):
                                subscription?.updateRenderingPath(isTiledCodec: isTiledCodec)
                                useCanvasRendering = isTiledCodec
                            default:
                                break
                            }
                        }
                }
                
#if os(iOS)
                // .frame(width: geometry.size.width, height: geometry.size.height + 10)
                // .position(x: geometry.frame(in: .local).midX, y: geometry.frame(in: .local).midY - 5)
#endif
#if os(macOS)
                /*
                 .onTapGesture {
                 client.hidioController.enableCaptureLock()
                 }
                 */
#endif
                
#if os(iOS)
                FloatingPalette(
                    actions: [.softwareKeyboard, .toggleZoomMode(zoomController.mode == .cursorTracking ? .free : .cursorTracking)],
                ) { action in
                    self.handlePaletteAction(action)
                }
#endif
            } // zstack
        } // geometryreader
    }
    
    private func fittedProjectionRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        
#if os(iOS)
        /// '잃어버린 10포인트'
        /// - 어째서인지 iOS에서만 툴바 - 메인 뷰 사이에 10포인트의 갭이 있음
        /// - 그런데 이게 원인을 모르겠음
        /// - position: fixed; left: 0; top: -10; 같은 짓을 함으로써 해결함
        // let patchedSize = CGSize(width: size.width, height: size.height + 10)
        let patchedSize = size
#else
        let patchedSize = size
#endif
        
        
        let containerRatio = patchedSize.width / patchedSize.height
        if containerRatio > aspectRatio {
            let height = patchedSize.height
            let width = height * aspectRatio
            let x = (patchedSize.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: height)
        } else {
            let width = patchedSize.width
            let height = width / aspectRatio
            let y = (patchedSize.height - height) / 2
            return CGRect(x: 0, y: y, width: width, height: height)
        }
    }
    
    
#if os(iOS)
    func handlePaletteAction(_ action: FloatingPaletteAction) {
        switch action {
        case .softwareKeyboard:
            shouldPresentKeyboard.toggle()
        case .toggleZoomMode:
            zoomController.cycleMode()
            // 커서추적 모드 진입 직후, 현재 커서 위치로 즉시 뷰포트 이동
            if zoomController.mode == .cursorTracking {
                snapViewportToCursor()
            }
        }
    }

    private func snapViewportToCursor() {
        let csSize = cursorSourceSize
        guard csSize.width > 0, csSize.height > 0 else { return }
        let pos = projection.cursorState.position
        let normalized = CGPoint(
            x: pos.x / csSize.width,
            y: pos.y / csSize.height
        )
        zoomController.centerViewportOnCursor(normalizedCursorPosition: normalized)
    }
#endif
    
}
