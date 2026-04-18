//
//  DisplaySwitcherSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/2/26.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import SiriusKitClient

extension View {
    @ViewBuilder
    func sessionOverlay<Content: View, SubContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder subcontent: @escaping () -> SubContent
    ) -> some View {
        self
            .modifier(SessionOverlayModifier(isPresented: isPresented, overlayContent: content, overlaySubcontent: subcontent))
    }
}

struct SessionOverlayModifier<OverlayContent: View, OverlaySubContent: View>: ViewModifier {
    @Binding
    var isPresented: Bool
    
    @ViewBuilder
    var overlayContent: () -> OverlayContent
    
    var overlaySubcontent: (() -> OverlaySubContent)? = nil

    init(
        isPresented: Binding<Bool>,
        overlayContent: @escaping () -> OverlayContent,
        overlaySubcontent: (() -> OverlaySubContent)? = nil
    ) {
        self._isPresented = isPresented
        self.overlayContent = overlayContent
        self.overlaySubcontent = overlaySubcontent
    }
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack(alignment: .bottom) {
                        ZStack {
                            Rectangle()
                                .fill(.black.opacity(0.5))
                            VStack {
                                Spacer()
                                overlaySubcontent?()
                                Spacer()
                            }
                        }
                        .onTapGesture {
                            isPresented = false
                        }
                        ZStack {
                            LinearGradient(stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.3),
                                .init(color: .black.opacity(0.0), location: 1.0),
                            ], startPoint: .bottom, endPoint: .top)
                            overlayContent()
                                .environment(\.colorScheme, .dark)
                                .safeAreaPadding(.bottom)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .ignoresSafeArea(.all)
                    .transition(.opacity.animation(.easeInOut))
                }
            }
    }
}

struct DisplayLayoutRendererView: View {
    let displays: [DisplayInfo]
    
    var entireViewport: CGRect {
        var viewport = CGRect.zero
        for display in displays {
            viewport = viewport.union(display.bounds.cgRect)
        }
        
        return viewport
    }
    
    // TODO: maxWidth, maxHeight로 화면 안 벗어나게 막아야 함
    var body: some View {
        GeometryReader { geomProxy in
            let rendererWidth = geomProxy.size.width
            let viewport = self.entireViewport
            let scale = rendererWidth / viewport.width
            
            let scaledSize = CGSize(
                width: viewport.width * scale,
                height: viewport.height * scale
            )
            
            
            ZStack(alignment: .topLeading) {
                ForEach(displays.sorted { $0.displayID < $1.displayID }, id: \.displayID) { display in
                    let isPrimary = display.state.isPrimary
                    
                    let scaled = CGRect(
                        x: display.bounds.x * scale,
                        y: display.bounds.y * scale,
                        width: display.bounds.width * scale,
                        height: display.bounds.height * scale
                    )
                    
                    VStack {
                        Spacer()
                        Text(display.displayName)
                            .bold()
                        Spacer()
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(width: scaled.width, height: scaled.height)
                    .background {
                        displayThumbnailView(for: display)
                    }
                    // isPrimary가 아니라 현재 프로젝션 중인 디스플레이가 red여야 하지 않을까?
                    .border(isPrimary ? .red : .black)
                    .position(x: scaled.midX, y: scaled.midY)
                }
                
                Text("[DEBUG] scaled: \(scaledSize)")
            }
            .frame(width: scaledSize.width, height: scaledSize.height)
            .position(x: geomProxy.frame(in: .local).midX, y: geomProxy.frame(in: .local).midY)
        }
        .frame(maxWidth: 480, maxHeight: 480)
    }
    
    @ViewBuilder
    private func displayThumbnailView(for display: DisplayInfo) -> some View {
        ZStack {
            if let thumbnail = display.thumbnail, let image = platformImage(from: thumbnail) {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Rectangle()
                .fill(.white)
                .opacity(0.3)
        }
    }

    private func platformImage(from data: Data) -> CGImage? {
        #if os(macOS)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return UIImage(data: data)?.cgImage
        #endif
    }
}

struct DisplaySwitcherSheetItem: View {
    @Environment(\.dismiss)
    var dismiss

    let display: DisplayInfo
    let action: (Int) -> Void
    var onDetach: ((Int) async throws -> Void)? = nil

    var body: some View {
        VStack {
            Button {
                action(Int(display.displayID))
                dismiss()
            } label: {
                VStack {
                    displayThumbnailView(for: display)
                    Text(display.displayName.withFallback(String(localized: "main.display_switcher.unnamed", defaultValue: "(이름 없음)")))
                        .lineLimit(1)
                }
                .frame(width: 160)
            }
            .buttonStyle(.plain)
            
            if let onDetach {
                Button {
                    Task {
                        try? await onDetach(Int(display.displayID))
                        dismiss()
                    }
                } label: {
                    Label(String(localized: "main.display_switcher.open_in_new_window", defaultValue: "별도 창으로 열기"), systemImage: "macwindow.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private func displayThumbnailView(for display: DisplayInfo) -> some View {
        Group {
            if let thumbnail = display.thumbnail, let image = platformImage(from: thumbnail) {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.black)
            }
        }
        .frame(width: 160, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func platformImage(from data: Data) -> CGImage? {
        #if os(macOS)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return UIImage(data: data)?.cgImage
        #endif
    }
}

struct DisplaySwitcherSheetAddVirtualDisplayItem: View {
    @Environment(\.dismiss)
    var dismiss

    let action: (Int) -> Void

    var body: some View {
        VStack {
            Button {
                action(-1)
                dismiss()
            } label: {
                VStack {
                    VStack {
                        Image(systemName: "plus")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, height: 48)
                    }
                    .environment(\.colorScheme, .light)
                    .frame(width: 160, height: 120)
                    .background(.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("새 가상 디스플레이")
                        .lineLimit(1)
                }
                .frame(width: 160)
            }
            .buttonStyle(.plain)
        }
    }
}

struct DisplaySwitcherSheet: View {
    @Environment(\.dismiss)
    var dismiss
    
    let displays: [DisplayInfo]
    let currentActive: Int?
    
    let action: (Int) -> Void
    var onDetach: ((Int) async throws -> Void)? = nil

    var body: some View {
        VStack {
            Text(markdown: String(localized: "main.display_switcher.title", defaultValue: "디스플레이 전환"))
                .font(.headline)
                .padding()

            ScrollView(.horizontal) {
                HStack(spacing: 32) {
                    ForEach(displays.sorted { $0.displayID < $1.displayID }, id: \.displayID) { display in
                        DisplaySwitcherSheetItem(display: display, action: action, onDetach: onDetach)
                    }
                    
                    DisplaySwitcherSheetAddVirtualDisplayItem(action: action)
                }
                .padding()
            }
        }
        .padding()
    }

   
}

#Preview {
    @Previewable
    @State
    var shouldPresentSheet: Bool = true
    
    let displays: [DisplayInfo] = [
        .init(
            displayID: 1,
            kind: .internal,
            displayName: "내장 디스플레이",
            state: .init(isPrimary: true, isConnected: true, isActive: true),
            bounds: .init(x: 0, y: 0, width: 1920, height: 1080),
            refreshRate: 60.0,
            colorDepth: .bit8,
            dynamicRange: .hdr,
            colorProfile: .displayP3,
            physicalSizeInfo: .init(physicalSize: .init(width: 344, height: 194), dpi: 163),
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        ),
        .init(
            displayID: 2,
            kind: .external,
            displayName: "LG SDQHD",
            state: .init(isPrimary: false, isConnected: true, isActive: true),
            bounds: .init(x: 1920, y: 0, width: 3840, height: 2160),
            refreshRate: 120.0,
            colorDepth: .bit8,
            dynamicRange: .sdr,
            colorProfile: .displayP3,
            physicalSizeInfo: .init(physicalSize: .init(width: 344, height: 194), dpi: 163),
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        ),
        .init(
            displayID: 3,
            kind: .external,
            displayName: "엄청나게 긴 이름을 가진 싸구려 모니터",
            state: .init(isPrimary: false, isConnected: true, isActive: true),
            bounds: .init(x: 1920, y: 2160, width: 2560, height: 1440),
            refreshRate: 120.0,
            colorDepth: .bit8,
            dynamicRange: .sdr,
            colorProfile: .displayP3,
            physicalSizeInfo: .init(physicalSize: .init(width: 344, height: 194), dpi: 163),
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        ),
        /*
        .init(
            displayID: 4,
            kind: .external,
            displayName: "",
            state: .init(isPrimary: false, isConnected: true, isActive: true),
            bounds: .init(x: 1920, y: 0, width: 3840, height: 2160),
            refreshRate: 120.0,
            colorDepth: .bit8,
            dynamicRange: .sdr,
            colorProfile: .displayP3,
            physicalSizeInfo: .init(physicalSize: .init(width: 344, height: 194), dpi: 163),
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        ),
        .init(
            displayID: 5,
            kind: .external,
            displayName: "죽음",
            state: .init(isPrimary: false, isConnected: true, isActive: true),
            bounds: .init(x: 1920, y: 0, width: 3840, height: 2160),
            refreshRate: 120.0,
            colorDepth: .bit8,
            dynamicRange: .sdr,
            colorProfile: .displayP3,
            physicalSizeInfo: .init(physicalSize: .init(width: 344, height: 194), dpi: 163),
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        ),
        .init(
            displayID: 6,
            kind: .external,
            displayName: "죽음 #2",
            state: .init(isPrimary: false, isConnected: true, isActive: true),
            bounds: .init(x: 1920, y: 0, width: 3840, height: 2160),
            refreshRate: 120.0,
            colorDepth: .bit8,
            dynamicRange: .sdr,
            colorProfile: .displayP3,
            physicalSizeInfo: .init(physicalSize: .init(width: 344, height: 194), dpi: 163),
            scaleFactor: 1.0,
            thumbnail: nil,
            metadata: [:],
            flags: 0
        ),
         */
    ]
    
    VStack {
        Button {
            shouldPresentSheet = true
        } label: {
            Text("디스플레이 전환 시트 열기")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.red)
    .sessionOverlay(isPresented: $shouldPresentSheet) {
        DisplaySwitcherSheet(displays: displays, currentActive: nil) { displayID in
            print("선택된 디스플레이 ID: \(displayID)")
        }
    } subcontent: {
        DisplayLayoutRendererView(displays: displays)
    }
    /*
    .popover(isPresented: $shouldPresentSheet) {
    }
     */
    /*
    .sheet(isPresented: $shouldPresentSheet) {
        DisplaySwitcherSheet(displays: displays, currentActive: nil) { displayID in
            print("선택된 디스플레이 ID: \(displayID)")
        }
            .presentationDragIndicator(.visible)
            .presentationSizing(.fitted)
    }
     */
}

fileprivate extension String {
    func withFallback(_ fallback: String) -> String {
        if self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback
        }
        return self
    }
}
