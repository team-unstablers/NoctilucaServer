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

enum ProjectionSourceDescriptor: CustomDebugStringConvertible, Equatable, Hashable {
    case sessionID(UUID)
    case displayID(Int)
    
    var debugDescription: String {
        switch self {
        case .sessionID(let sessionID):
            return "Session ID (\(sessionID))"
        case .displayID(let displayID):
            return "Display ID #\(displayID)"
        }
    }
}

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
    private var scale: CGFloat = 1.0
    @State
    private var lastScale: CGFloat = 1.0
    @State
    private var offset: CGSize = .zero
    @State
    private var lastOffset: CGSize = .zero
    @State
    private var cursorPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @State
    private var projectionAspectRatio: CGFloat = 16.0 / 9.0
    @State
    private var lastPerformanceReport: ProjectionPerformanceReport?
    
#if os(iOS)
    @State private var shouldPresentKeyboard: Bool = false
    @StateObject private var uiKitKeyboard = HIDIOUIKitKeyboard()
    @EnvironmentObject private var windowViewModel: SessionWindowViewModel
#endif
    
    private func syncSourceMetadata() {
        guard let source else { return }
        self.sourceSize = source.size
        if source.size.width > 0, source.size.height > 0 {
            self.projectionAspectRatio = source.size.width / source.size.height
        }
    }

    private func syncMouseScope() {
        guard case .displayID(let displayID) = sourceDescriptor else {
            return
        }

        let scope = CursorPositionScope.displayId(Int32(displayID))

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
            ZStack(alignment: .topLeading) {
                let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                
                if let displayLayer = subscription?.displayLayer {
                    SampleBufferDisplayView(displayLayer: displayLayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(offset)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .scaleEffect(scale)
                }
               
                // Metal Cursor Overlay
                // ZStack 위에 투명하게 얹음.
                // allowsHitTesting(false) 필수: 마우스 클릭이 아래 뷰(입력 캡처)로 전달되어야 함.
                // displayID 기반 visibility는 CursorRenderer 내부에서 처리 (SwiftUI 업데이트 지연 방지)
                if case .displayID(let displayID) = sourceDescriptor {
                    MetalCursorView(cursorState: projection.cursorState, sourceSize: sourceSize, targetDisplayID: displayID)
                        .offset(offset)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .scaleEffect(scale)
                }
                
#if os(macOS)
                if hidio.sessionMode == .shared,
                   let mouse = hidio.session.currentMouse as? HIDIOAppKitPointer
                {
                    HIDIOAppKitMouseView(pointer: mouse)
                        .offset(offset)
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
                    )
                    .offset(offset)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
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
            .background(.black)
            .onAppear {
                syncSourceMetadata()
                syncMouseScope()
            }
            .onChange(of: source?.id) { _, _ in
                syncSourceMetadata()
            }
            .onChange(of: sourceDescriptor) { _, _ in
                syncMouseScope()
            }
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
                        default:
                            break
                        }
                    }
            }
#if os(macOS)
            /*
            .onTapGesture {
                client.hidioController.enableCaptureLock()
            }
             */
#endif
        }
    }
    
    private func fittedProjectionRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        
        let containerRatio = size.width / size.height
        if containerRatio > aspectRatio {
            let height = size.height
            let width = height * aspectRatio
            let x = (size.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: height)
        } else {
            let width = size.width
            let height = width / aspectRatio
            let y = (size.height - height) / 2
            return CGRect(x: 0, y: y, width: width, height: height)
        }
    }
    
    
}
