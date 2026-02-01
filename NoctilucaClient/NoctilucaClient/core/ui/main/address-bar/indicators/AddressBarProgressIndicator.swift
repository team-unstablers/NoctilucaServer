//
//  AddressBarProgressIndicator.swift
//  NoctilucaClient
//

import SwiftUI

struct AddressBarProgressIndicator: View {
    let progress: Double

    private enum Phase {
        case idle        // 숨겨진 상태
        case progressing // 진행 중
        case fadingOut   // 100% 도달 후 페이드아웃 중
    }

    @State private var phase: Phase = .idle
    @State private var animatedProgress: Double = 0.0
    @State private var opacity: Double = 0.0
    @State private var fadeOutTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.tint)
                .frame(width: proxy.size.width * animatedProgress, height: 4)
                .offset(y: proxy.size.height - 4)
                .opacity(opacity)
        }
        .onChange(of: progress) { _, newValue in
            transition(to: newValue)
        }
        .onAppear {
            initializeState()
        }
    }

    private func initializeState() {
        if progress > 0.0 && progress < 1.0 {
            phase = .progressing
            animatedProgress = progress
            opacity = 1.0
        } else {
            phase = .idle
            animatedProgress = 0.0
            opacity = 0.0
        }
    }

    private func transition(to newProgress: Double) {
        // 진행 중인 페이드아웃 Task 취소
        fadeOutTask?.cancel()
        fadeOutTask = nil

        switch phase {
        case .idle:
            handleIdleTransition(to: newProgress)

        case .progressing:
            handleProgressingTransition(to: newProgress)

        case .fadingOut:
            handleFadingOutTransition(to: newProgress)
        }
    }

    private func handleIdleTransition(to newProgress: Double) {
        guard newProgress > 0.0 else { return }

        // idle → progressing: 페이드인 + width 애니메이션
        phase = .progressing
        withAnimation(.easeInOut(duration: 0.2)) {
            opacity = 1.0
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            animatedProgress = newProgress
        }

        // 100%면 바로 페이드아웃 스케줄
        if newProgress >= 1.0 {
            scheduleFadeOut()
        }
    }

    private func handleProgressingTransition(to newProgress: Double) {
        if newProgress >= 1.0 {
            // progressing → fadingOut
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newProgress
            }
            scheduleFadeOut()
        } else if newProgress == 0.0 {
            // 외부에서 리셋 → idle
            resetToIdle()
        } else {
            // 계속 진행
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newProgress
            }
        }
    }

    private func handleFadingOutTransition(to newProgress: Double) {
        if newProgress > 0.0 && newProgress < 1.0 {
            // fadingOut → progressing: 새 작업 시작됨
            phase = .progressing
            withAnimation(.easeInOut(duration: 0.2)) {
                opacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newProgress
            }
        } else if newProgress == 0.0 {
            // 즉시 idle로
            resetToIdle()
        }
        // newProgress >= 1.0이면 이미 fadingOut 중이므로 무시
    }

    private func scheduleFadeOut() {
        phase = .fadingOut
        fadeOutTask = Task {
            // width 애니메이션 완료 대기 (0.3초)
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                // 여전히 fadingOut 상태인지 확인 (다른 상태로 전환됐으면 무시)
                guard phase == .fadingOut else { return }

                withAnimation(.easeInOut(duration: 0.2)) {
                    opacity = 0.0
                } completion: {
                    // 여전히 fadingOut인지 다시 확인 (애니메이션 중 다른 상태로 전환됐으면 무시)
                    guard phase == .fadingOut else { return }
                    // 페이드아웃 완료 → idle
                    phase = .idle
                    animatedProgress = 0.0
                }
            }
        }
    }

    private func resetToIdle() {
        phase = .idle
        animatedProgress = 0.0
        opacity = 0.0
    }
}

// MARK: - Preview

private struct AddressBarProgressIndicatorPreviewContainer: View {
    @State private var progress: Double = 0.0

    var body: some View {
        VStack(spacing: 20) {
            // 프로그레스 바 표시 영역 (실제 AddressBar와 비슷한 형태)
            RoundedRectangle(cornerRadius: 19)
                .fill(.gray.opacity(0.2))
                .frame(height: 38)
                .overlay(alignment: .bottom) {
                    AddressBarProgressIndicator(progress: progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 19))

            Text("Progress: \(Int(progress * 100))%")
                .font(.caption)

            // 테스트 버튼들
            HStack(spacing: 12) {
                Button("0%") { progress = 0.0 }
                Button("50%") { progress = 0.5 }
                Button("100%") { progress = 1.0 }
            }
        }
        .padding()
    }
}

#Preview("Progress Indicator") {
    AddressBarProgressIndicatorPreviewContainer()
        .frame(width: 400, height: 200)
}
