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
    
    @StateObject
    var remoteSession: RemoteSession
    
    var client: NoctilucaClient {
        remoteSession.client
    }
    
    @StateObject
    var projection: RemoteSession.Projection
    
    @State
    var sourceDescriptor: AttachSource
    
    @State
    var source: ProjectionSession?
    
    @State
    var sourceSize: CGSize = .zero
    
    init(remoteSession: RemoteSession, projection: RemoteSession.Projection, source: AttachSource) {
        self._remoteSession = StateObject(wrappedValue: remoteSession)
        self._projection = StateObject(wrappedValue: projection)
        
        self.sourceDescriptor = source
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
                return
            }
            
            self.source = source
        case .displayID(let displayID):
            guard let source = projection.projectionSessions.values.first(where: { $0.displayID == displayID }) else {
                return
            }
            
            self.source = source
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
                
                // TODO: 추후엔 Metal shader로 그리는 것이 바람직함
                let cursor = projection.cursorState
                if let cursorImage = cursor.image {
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                    
                    let width = cursorImage.size.width
                    let height = cursorImage.size.height
                    
                    // TODO: use hotspot info from server
                    let hotspot = cursorImage.hotspot
                    
                    // SwiftUI .position places the CENTER of the view at the point.
                    // We want the TOP-LEFT (0,0) of the cursor image to be at the point.
                    // So we shift the position by +width/2, +height/2.
                    let position = CGPoint(
                        x: rect.minX + (cursor.position.x * rect.width) + (width / 2),
                        y: rect.minY + (cursor.position.y * rect.height) + (height / 2)
                    )
                    
                    Image(decorative: cursorImage.image, scale: 1.0, orientation: .up)
                        .position(position)
                        .scaleEffect(scale)
                        .offset(offset)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(source != nil) {
                $0.onReceive(source!.events) { event in
                    switch event {
                    case .sizeChanged(let size):
                        sourceSize = size
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
