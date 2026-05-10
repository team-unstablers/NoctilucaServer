//
//  WindowInfoOverlay.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/22/26.
//

#if os(macOS)

import SwiftUI

import SiriusKitClient

struct AppStreamWindowInfoOverlayContainer: View {
    @ObservedObject var store: ObservableWindowInfo
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        if settingsStore.settings.misc.showAppStreamWindowInfoOverlay {
            WindowInfoOverlay(store: store)
                .padding(8)
        }
    }
}

struct WindowInfoOverlay: View {
    @ObservedObject var store: ObservableWindowInfo

    @State private var isExpanded = false
    @State private var position: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private var currentOffset: CGSize {
        CGSize(
            width: position.width + dragOffset.width,
            height: position.height + dragOffset.height
        )
    }

    private var info: WindowInfo { store.windowInfo }

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .contentShape(Rectangle())
        .offset(currentOffset)
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        )
        .gesture(
            DragGesture(minimumDistance: 5)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    position.width += value.translation.width
                    position.height += value.translation.height
                }
        )
    }

    // MARK: - Compact View

    private var compactView: some View {
        HStack(spacing: 6) {
            Text("#\(info.windowID)")
            Text("|").foregroundStyle(.secondary)
            Text(info.role.displayName)
            Text("|").foregroundStyle(.secondary)
            Text("\(Int(info.bounds.width))\u{00D7}\(Int(info.bounds.height))")
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("**[WindowInfo]**")
            Text("Window ID: \(info.windowID)")
            Text("PID: \(info.pid)")
            Text("Title: \(info.windowTitle)")
            Text("App: \(info.applicationName) (\(info.applicationBundleID))")
            Text("Class: \(info.windowClass)")
            Text("Role: \(info.role.displayName)")
            Text("Bounds: (\(Int(info.bounds.x)), \(Int(info.bounds.y))) \(Int(info.bounds.width))\u{00D7}\(Int(info.bounds.height))")

            if let parentID = info.parentWindowID {
                Text("Parent: \(parentID)")
            }

            Text("")
            Text("**[Flags]** \(flagsDescription)")
            Text("**[Hints]** \(hintsDescription)")

            if !info.metadata.isEmpty {
                Text("")
                Text("**[Metadata]**")
                ForEach(info.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("  \(key) = \(value)")
                        .font(.system(size: 11).monospaced())
                }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

    // MARK: - Helpers

    private var flagsDescription: String {
        let active = WindowInfoFlags.knownFlags.compactMap { (flag, name) in
            info.flags.contains(flag) ? name : nil
        }
        return active.isEmpty ? "none" : active.joined(separator: ", ")
    }

    private var hintsDescription: String {
        let active = WindowHint.knownHints.compactMap { (hint, name) in
            info.hints.contains(hint) ? name : nil
        }
        return active.isEmpty ? "none" : active.joined(separator: ", ")
    }
}

// MARK: - Display Name Extensions

private extension WindowRole {
    var displayName: String {
        switch self {
        case .normal: return "normal"
        case .dialog: return "dialog"
        case .tooltip: return "tooltip"
        case .menu: return "menu"
        case .notification: return "notification"
        case .unknown: return "unknown"
        default: return "role(\(rawValue))"
        }
    }
}

private extension WindowInfoFlags {
    static let knownFlags: [(WindowInfoFlags, String)] = [
        (.isFocused, "focused"),
        (.isHidden, "hidden"),
        (.noWindowDecoration, "noDecoration"),
        (.skipWindowEntry, "skipEntry"),
        (.isMinimized, "minimized"),
        (.isMaximized, "maximized"),
        (.isFullscreen, "fullscreen"),
        (.cannotMinimize, "cannotMinimize"),
        (.cannotMaximize, "cannotMaximize"),
        (.cannotFullscreen, "cannotFullscreen"),
        (.isTopmost, "topmost"),
        (.isBottommost, "bottommost"),
        (.skipCompositor, "skipCompositor"),
    ]
}

private extension WindowHint {
    static let knownHints: [(WindowHint, String)] = [
        (.systemUI, "systemUI"),
        (.notResponding, "notResponding"),
        (.inaccessible, "inaccessible"),
        (.protectedContent, "protectedContent"),
        (.aggressiveProtectedContent, "aggressiveProtected"),
        (.notVisibleOnScreen, "notVisible"),
        (.staticContent, "static"),
        (.dynamicContent, "dynamic"),
        (.hasShadow, "shadow"),
        (.hasTransparency, "transparency"),
    ]
}

#endif
