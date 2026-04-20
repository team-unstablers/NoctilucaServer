//
//  FullscreenOverlayView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(iOS)
import SwiftUI

/// 전체 화면 모드에서 상단 엣지 스와이프 시 일시적으로 표시되는 오버레이 툴바
struct FullscreenOverlayView: View {
    @Environment(SessionWindowViewModel.self)
    var viewModel: SessionWindowViewModel

    @EnvironmentObject
    var settingsStore: SettingsStore

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    Task { @MainActor in
                        await viewModel.stopSession()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                }

                MainToolbarAddressBar(
                    viewModel: viewModel,
                    settingsStore: settingsStore,
                    focusBinding: .none
                )
                .allowsHitTesting(false)
                .frame(maxWidth: 400)

                Button {
                    viewModel.shouldPresentDisplaySwitchSheet.toggle()
                    viewModel.scheduleAutoHideOverlay()
                } label: {
                    Image(systemName: "display.2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.foreground, .clear)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 36, height: 36)

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.isFullscreen = false
                        viewModel.isFullscreenOverlayVisible = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#endif
