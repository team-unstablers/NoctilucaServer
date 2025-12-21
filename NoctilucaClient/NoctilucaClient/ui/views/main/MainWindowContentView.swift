//
//  NewConnectionPhaseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

import AVFoundation

import SiriusKitClient

#if os(macOS)
import AppKit
#endif

struct MainWindowNewConnectionPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text("Noctiluca ")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Navigator")
                        .font(.largeTitle)
                        .fontWeight(.light)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                
                Text("버전 \(NoctilucaMeta.version)")
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            Text("저장된 호스트 목록")
                .font(.title)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack {
                    ContactItemView(item: .init(name: "집 컴퓨터", endpointURL: "localhost:8283")) { action in
                        switch action {
                        case .launch:
                            Task {
                                try? await viewModel.startSession(endpointURL: "localhost:8283")
                            }
                        case .edit:
                            break
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainWindowConnectingPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel

    @State
    var isLogAreaVisible: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading) {
                
                Spacer()
                
                HStack(spacing: 0) {
                    Text("연결 중")
                        .font(.largeTitle)
                        .fontWeight(.light)
                }
                .padding(.bottom, 2)
                
                Text("\(self.viewModel.endpointURL)에 연결하고 있습니다...")
                    .padding(.bottom, 32)
                
                Spacer()
                
                
                VStack {
                }
                .frame(maxWidth: .infinity)
            }
            
            
                Text(
                    self.viewModel.connectionLog.joined(separator: "\n")
                )
                .font(.system(size: 12).monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
#if os(macOS)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(NSColor.windowBackgroundColor),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(isLogAreaVisible ? 0.0 : 1.0)
                }
#endif
                .onHover { hoverState in
                    if hoverState {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = true
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = false
                        }
                    }
                    
                }
        }
        .padding(24)
    }
}

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

#if os(macOS)
private struct InputWarningBanner: View {
    let warning: InputWarning
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(warning.title)
                .font(.headline)
            Text(warning.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("설정 열기") {
                    openSettings()
                }
                Button("다시 시도") {
                    retry()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(radius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
#endif


struct MainWindowContentView: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass)
    var horizontalSizeClass
#endif
    
    @EnvironmentObject
    var viewModel: MainWindowViewModel
    
    var body: some View {
        switch viewModel.phase {
        case .newConnection:
            MainWindowNewConnectionPhaseContentView()
#if os(iOS)
                .safeAreaPadding(.vertical)
                .padding(.top, horizontalSizeClass == .compact ? 0 : 32)
#endif
        case .connecting:
            MainWindowConnectingPhaseContentView()
        case .connected:
            MainWindowMainPhaseContentView()
        default:
            EmptyView()
        }
        
    }
}

#Preview("NewConnectionPhase") {
    let viewModel = MainWindowViewModel()
    
    /*
    MainWindowContentView(viewModel: viewModel)
     */
    
    MainWindowNewConnectionPhaseContentView()
        .environmentObject(viewModel)
        .frame(minWidth: 640, minHeight: 480)
}

#Preview("ConnectingPhase") {
    let viewModel = MainWindowViewModel()
    
    MainWindowConnectingPhaseContentView()
        .environmentObject(viewModel)
        .frame(minWidth: 640, minHeight: 480)
}
