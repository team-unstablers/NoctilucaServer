//
//  MainWindowMainPhaseContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                if let displayLayer = viewModel.displayLayer {
                    SampleBufferDisplayView(displayLayer: displayLayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(offset)
                }

                if let session = viewModel.client?.projectionChannel?.sessions.first?.value,
                   let codec = session.codec
                {
                    PerformanceOverlay(codec: codec, rtt: viewModel.averagePingRTT)
                        .padding(16)
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


            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(viewModel.client != nil) {
                $0.onReceive(viewModel.client!.uiEvents) { event in
                    guard case .FIXME_projectionStarted(let projectionSession) = event else {
                        return
                    }

                    viewModel.displayLayer = projectionSession.displayLayer
                }
            }
        }
    }

}
