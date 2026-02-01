//
//  MainWindowMainPhaseContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

struct MainWindowMainPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cursorPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var projectionAspectRatio: CGFloat = 16.0 / 9.0

#if os(iOS)
    @State private var shouldPresentKeyboard: Bool = false
    @StateObject private var uiKitKeyboard = HIDIOUIKitKeyboard()
    @EnvironmentObject private var settingsStore: SettingsStore
#endif

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let displayLayer = viewModel.displayLayer {
                    SampleBufferDisplayView(displayLayer: displayLayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(offset)
                }

                /*
                if let session = viewModel.client?.projectionChannel?.sessions.first?.value,
                   let codec = session.codec
                {
                    PerformanceOverlay(codec: codec, rtt: viewModel.averagePingRTT)
                        .padding(16)
                }
                 */
                
                if let cursorImage = viewModel.client?.projectionChannel?.cursorImage {
                    let rect = fittedProjectionRect(in: geometry.size, aspectRatio: projectionAspectRatio)
                    let width = CGFloat(cursorImage.width)
                    let height = CGFloat(cursorImage.height)
                    
                    // SwiftUI .position places the CENTER of the view at the point.
                    // We want the TOP-LEFT (0,0) of the cursor image to be at the point.
                    // So we shift the position by +width/2, +height/2.
                    // (Assuming hotspot is at 0,0 for now. Ideal solution requires hotspot info from server)
                    let position = CGPoint(
                        x: rect.minX + (cursorPosition.x * rect.width) + (width / 2),
                        y: rect.minY + (cursorPosition.y * rect.height) + (height / 2)
                    )

                    Image(decorative: cursorImage, scale: 1.0, orientation: .up)
                        .position(position)
                        .scaleEffect(scale)
                        .offset(offset)
                }
                
                

#if os(macOS)
                if let warning = viewModel.inputWarning {
                    InputWarningBanner(
                        warning: warning,
                        openSettings: {
                            TCCUtil.shared.openSystemPreferences(for: .inputMonitoring)
                        },
                        retry: {
                            TCCUtil.shared.requestAccess(for: .inputMonitoring)
                            viewModel.retryInputRedirection()
                        }
                    )
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
#endif
                /*
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    // .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                withAnimation(.spring()) {
                                    // toolbarVisible = false
                                }

                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.25), 4)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                withAnimation(.spring()) {
                                    if scale < 1 {
                                        scale = 1
                                        offset = .zero
                                    }
                                }
                            }
                            .simultaneously(with:
                                                DragGesture()
                                .onChanged { value in
                                    if scale > 1 {
                                        withAnimation(.spring()) {
                                            // toolbarVisible = false
                                        }

                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset

                                    // 화면 밖으로 나가지 않도록 제한
                                    withAnimation(.spring()) {
                                        let maxX = (geometry.size.width * (scale - 1)) / 2
                                        let maxY = (geometry.size.height * (scale - 1)) / 2

                                        offset.width = min(max(offset.width, -maxX), maxX)
                                        offset.height = min(max(offset.height, -maxY), maxY)
                                        lastOffset = offset
                                    }
                                }
                                           )
                    )
                    .onTapGesture(count: 1) {
                        withAnimation(.spring()) {
                            // toolbarVisible = !toolbarVisible
                        }
                    }
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            // toolbarVisible = false
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2
                            }
                        }
                    }
                 */
                
#if os(iOS)
                HIDIOUIKitMouseView(
                    client: viewModel.client,
                    mode: $settingsStore.settings.input.touchInputMode,
                    trackpadMoveMultiplier: $settingsStore.settings.input.trackpadMoveMultiplier,
                    cursorPosition: $cursorPosition,
                    aspectRatio: $projectionAspectRatio
                )

                HIDIOUIKitKeyboardInputHost(
                    client: viewModel.client,
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
                viewModel.client?.hidioController.enableCaptureLock()
            }
#endif
#if os(iOS)
            .onReceive((viewModel.client?.uiEvents.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher())) { event in
                guard case .FIXME_projectionStarted(let session) = event else {
                    return
                }

                projectionAspectRatio = session.size.width / session.size.height
            }
#endif
#if os(iOS)
            .onChange(of: viewModel.phase) { _, newValue in
                if newValue != .connected {
                    shouldPresentKeyboard = false
                }
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
