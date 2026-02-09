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
    
    @State
    var source: ProjectionSession?
    
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
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var windowViewModel: SessionWindowViewModel
#endif
    
    func resolveSource(_ descriptor: ProjectionSourceDescriptor) {
        Self.logger.info("resolving projection session from source descriptor \(descriptor.debugDescription)")
        
        switch descriptor {
        case .sessionID(let sessionID):
            guard let source = projection.projectionSessions[sessionID] else {
                Self.logger.error("failed to resolve source \(descriptor.debugDescription)")
                return
            }
            
            self.source = source
            self.sourceSize = source.size
            if source.size.width > 0, source.size.height > 0 {
                self.projectionAspectRatio = source.size.width / source.size.height
            }
        case .displayID(let displayID):
            Self.logger.debug("resolveSource: \(projection.projectionSessions)")
            guard let source = projection.projectionSessions.values.first(where: { $0.displayID == displayID }) else {
                Self.logger.error("failed to resolve source \(descriptor.debugDescription)")
                return
            }
            
            self.source = source
            self.sourceSize = source.size
            if source.size.width > 0, source.size.height > 0 {
                self.projectionAspectRatio = source.size.width / source.size.height
            }
        }
    }
    
    var body: some View {
        // TODO: preparingView unless(remoteSession.projection)
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                
                if let displayLayer = source?.displayLayer {
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
                // 커서 이미지가 있을 때만 렌더링하여 불필요한 리소스 소모 방지
                if projection.cursorState.image != nil {
                    MetalCursorView(cursorState: projection.cursorState, sourceSize: sourceSize)
                        .offset(offset)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        // 화면 줌인/아웃 시 커서도 같이 확대/축소 및 이동
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
            .onChange(of: sourceDescriptor) { _, newValue in
                self.resolveSource(newValue)
            }
            .onAppear {
                if (source == nil) {
                    self.resolveSource(self.sourceDescriptor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(source == nil) {
                $0
                    // source를 좀 더 적극적으로 resolve 시도한다.
                    .onReceive(client.projectionChannel.events) { event in
                        switch event {
                        case .sessionCreated(_):
                            self.resolveSource(sourceDescriptor)
                        default:
                            break
                        }
                    }
                    // projectionSessions 딕셔너리가 업데이트되면 재시도한다.
                    // (SubDisplayWindow 등에서 뷰 생성 시점에 .sessionCreated 이벤트를
                    //  놓칠 수 있는 race condition 방지)
                    .onReceive(projection.$projectionSessions) { _ in
                        self.resolveSource(sourceDescriptor)
                    }
            }
            .if(source != nil) {
                $0.onReceive(source!.events) { event in
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
#if os(iOS)
            /*
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HIDIOUIKitKeyboardHelperView(
                    keyboard: uiKitKeyboard,
                    isVisible: shouldPresentKeyboard
                )
            }
             */
#endif
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
