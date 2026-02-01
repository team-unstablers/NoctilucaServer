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
    
    enum AttachSource: CustomDebugStringConvertible {
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
    
    @ObservedObject
    var remoteSession: RemoteSession
    
    var client: NoctilucaClient {
        remoteSession.client
    }
    
    @ObservedObject
    var projection: RemoteSession.Projection
    
    @State
    var sourceDescriptor: AttachSource
    
    @State
    var source: ProjectionSession?
    
    @State
    var sourceSize: CGSize = .zero
    
    init(remoteSession: RemoteSession, projection: RemoteSession.Projection, source: AttachSource) {
        self.remoteSession = remoteSession
        self.projection = projection
        
        self._sourceDescriptor = State(initialValue: source)
    }
    
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
    
#if os(iOS)
    @State private var shouldPresentKeyboard: Bool = false
    @StateObject private var uiKitKeyboard = HIDIOUIKitKeyboard()
    @EnvironmentObject private var settingsStore: SettingsStore
#endif
    
    func resolveSource(_ descriptor: AttachSource) {
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
                if let displayLayer = source?.displayLayer {
                    SampleBufferDisplayView(displayLayer: displayLayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(offset)
                }
                
                // Metal Cursor Overlay
                // ZStack 위에 투명하게 얹음.
                // allowsHitTesting(false) 필수: 마우스 클릭이 아래 뷰(입력 캡처)로 전달되어야 함.
                // 커서 이미지가 있을 때만 렌더링하여 불필요한 리소스 소모 방지
                if projection.cursorState.image != nil {
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                    
                    MetalCursorView(cursorState: projection.cursorState, sourceSize: sourceSize)
                        .offset(offset)
                        .background(.red.opacity(0.3))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        // 화면 줌인/아웃 시 커서도 같이 확대/축소 및 이동
                        .scaleEffect(scale)
                }
                
#if os(iOS)
                HIDIOUIKitMouseView(
                    client: remoteSession.client,
                    sessionSize: sourceSize,
                    mode: $settingsStore.settings.input.touchInputMode,
                    trackpadMoveMultiplier: $settingsStore.settings.input.trackpadMoveMultiplier,
                    cursorPosition: $cursorPosition,
                    aspectRatio: $projectionAspectRatio
                )
                
                HIDIOUIKitKeyboardInputHost(
                    client: remoteSession.client,
                    keyboard: uiKitKeyboard,
                    isPresented: $shouldPresentKeyboard
                )
                
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
#endif
            }
            .onAppear {
                if (source == nil) {
                    self.resolveSource(self.sourceDescriptor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(source == nil) {
                // source를 좀 더 적극적으로 resolve 시도한다.
                $0.onReceive(client.projectionChannel.events) { event in
                    switch event {
                    case .sessionCreated(_):
                        self.resolveSource(sourceDescriptor)
                    default:
                        break
                    }
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
                    default:
                        break
                    }
                }
            }
#if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HIDIOUIKitKeyboardHelperView(
                    keyboard: uiKitKeyboard,
                    isVisible: shouldPresentKeyboard
                )
            }
#endif
#if os(macOS)
            .onTapGesture {
                client.hidioController.enableCaptureLock()
            }
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
