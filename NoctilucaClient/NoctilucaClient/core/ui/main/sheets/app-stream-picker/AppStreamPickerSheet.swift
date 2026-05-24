//
//  AppStreamPickerSheet.swift
//  NoctilucaClient
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import SiriusKitClient

enum AppStreamPickerAction: Sendable {
    case selectApp(bundleId: String)
}

struct AppStreamPickerSheet: View {
    @Environment(\.dismiss)
    private var dismiss

    /// 앱 목록을 불러오는 클로저. 시트 열 때와 재시도 시에 호출된다.
    let listLoader: () async throws -> [ApplicationInfo]

    let actionHandler: (AppStreamPickerAction) async throws -> Void

    @State
    private var listState: ListState = .loading

    @State
    private var actionHandlerTask: Task<Void, Never>? = nil

    enum ListState {
        case loading
        case loaded([ApplicationInfo])
        case empty
        case failed(Error)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "main.app_stream_picker.title", defaultValue: "앱 선택"))
                .font(.headline)
                .padding(.top)

            contentView
                .frame(minHeight: 180)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .padding()
        .task {
            await loadList()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch listState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)

        case .loaded(let apps):
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(apps, id: \.bundleId) { app in
                        AppStreamPickerSheetItem(app: app) { bundleId in
                            self.invokeAction(.selectApp(bundleId: bundleId))
                        }
                    }
                }
                .padding(.vertical, 8)
            }

        case .empty:
            emptyPlaceholder(
                String(localized: "main.app_stream_picker.empty", defaultValue: "허용된 앱이 없습니다")
            )

        case .failed(let error):
            VStack(spacing: 12) {
                Text(String(localized: "main.app_stream_picker.failed", defaultValue: "앱 목록을 불러오지 못했습니다"))
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await loadList() }
                } label: {
                    Text(String(localized: "common.retry", defaultValue: "다시 시도"))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func emptyPlaceholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadList() async {
        listState = .loading
        do {
            let apps = try await listLoader()
            listState = apps.isEmpty ? .empty : .loaded(apps)
        } catch {
            listState = .failed(error)
        }
    }

    private func invokeAction(_ action: AppStreamPickerAction) {
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

struct AppStreamPickerSheetItem: View {
    let app: ApplicationInfo
    let action: (String) -> Void

    var body: some View {
        Button {
            action(app.bundleId)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    iconView
                        .frame(width: 80, height: 80)

                    if let dotColor = stateDotColor {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().stroke(.white, lineWidth: 1.5)
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                Text(app.displayName)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 96)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        if let iconData = app.icon, let image = platformImage(from: iconData) {
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.gray.opacity(0.25))
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var stateDotColor: Color? {
        if app.state == .foreground {
            return .green
        } else if app.state == .background {
            return .gray
        } else {
            return nil
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

#Preview {
    @Previewable
    @State
    var shouldPresentSheet: Bool = true

    let sampleApps: [ApplicationInfo] = [
        .init(
            bundleId: "com.apple.dt.Xcode",
            displayName: "Xcode",
            state: .foreground,
            windows: [],
            icon: nil,
            metadata: [:],
            hints: 0,
            flags: 0
        ),
        .init(
            bundleId: "com.apple.Safari",
            displayName: "Safari",
            state: .background,
            windows: [],
            icon: nil,
            metadata: [:],
            hints: 0,
            flags: 0
        ),
        .init(
            bundleId: "com.figma.Desktop",
            displayName: "Figma",
            state: .notRunning,
            windows: [],
            icon: nil,
            metadata: [:],
            hints: 0,
            flags: 0
        ),
    ]

    VStack {
        Button("앱 선택 시트 열기") {
            shouldPresentSheet = true
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.red)
    .sessionOverlay(isPresented: $shouldPresentSheet) {
        AppStreamPickerSheet(
            listLoader: { sampleApps },
            actionHandler: { action in
                print("선택: \(action)")
            }
        )
    } subcontent: {
        EmptyView()
    }
}
