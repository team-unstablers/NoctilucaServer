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

#if os(macOS)
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
#endif
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

    let action: () -> Void

    var body: some View {
        VStack {
            Button {
                action()
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

enum DisplaySwitcherAction: Sendable {
    case switchDisplay(displayID: Int)
    case createDetachedDisplay(displayID: Int)
    case createVirtualDisplay(spec: VirtualDisplaySpec)
    case destroyVirtualDisplay(identifier: UUID)
}

struct DisplaySwitcherSheet: View {
    @Environment(\.dismiss)
    var dismiss

    let displays: [DisplayInfo]
    let currentActive: Int?

    let actionHandler: ((DisplaySwitcherAction) async throws -> Void)
    
    @State
    var shouldPresentAddVirtualDisplaySheet: Bool = false
    
    @State
    var actionHandlerTask: Task<Void, Never>? = nil

    var body: some View {
        VStack {
            Text(markdown: String(localized: "main.display_switcher.title", defaultValue: "디스플레이 전환"))
                .font(.headline)
                .padding()

            ScrollView(.horizontal) {
                HStack(spacing: 32) {
                    ForEach(displays.sorted { $0.displayID < $1.displayID }, id: \.displayID) { display in
                        ZStack(alignment: .topTrailing) {
                            DisplaySwitcherSheetItem(display: display) { displayID in
                                self.invokeAction(action: .switchDisplay(displayID: displayID))
                            } onDetach: { displayID in
                                self.invokeAction(action: .createDetachedDisplay(displayID: displayID))
                            }
                            
                            if let virtualDisplayIdentifier = display.virtualDisplayIdentifier {
                                Button {
                                    self.invokeAction(action: .destroyVirtualDisplay(identifier: virtualDisplayIdentifier))
                                } label: {
                                    Image(systemName: "x.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.red)
                                        .background(.white, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 8, y: -8)
                            }
                        }
                    }

                    DisplaySwitcherSheetAddVirtualDisplayItem {
                        shouldPresentAddVirtualDisplaySheet = true
                    }
                }
                .padding()
            }
        }
        .padding()
        .sheet(isPresented: $shouldPresentAddVirtualDisplaySheet) {
            AddVirtualDisplaySheet { spec in
                try await actionHandler(.createVirtualDisplay(spec: spec))
            }
                .environment(\.colorScheme, .light)
        }
    }

    func invokeAction(action: DisplaySwitcherAction) {
        self.actionHandlerTask?.cancel()
        
        self.actionHandlerTask = Task {
            do {
                try await actionHandler(action)
            } catch {
                print(error)
                // FIXME
            }
        }
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
            rotation: .deg0,
            supportedSpecs: [],
            thumbnail: nil,
            metadata: [:],
            flags: 0,
            virtualDisplayIdentifier: nil
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
            rotation: .deg0,
            supportedSpecs: [],
            thumbnail: nil,
            metadata: [:],
            flags: 0,
            virtualDisplayIdentifier: nil
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
            rotation: .deg0,
            supportedSpecs: [],
            thumbnail: nil,
            metadata: [:],
            flags: 0,
            virtualDisplayIdentifier: UUID()
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
        DisplayLayoutModifierView(displays: displays) { operations, mainDisplayID in
            print("[Preview] applying operations: \(operations.count), mainDisplayID: \(String(describing: mainDisplayID))")
        }
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
