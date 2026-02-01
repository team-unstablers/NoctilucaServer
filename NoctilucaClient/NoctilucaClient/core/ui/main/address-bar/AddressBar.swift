//
//  AddressBar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

struct AddressBar: View {
    // MARK: - External Properties

    let endpointURL: String
    let securityIndicator: AddressBarSecurityIndicatorState?
    let qualityIndicator: AddressBarQualityIndicatorState?
    let rtt: TimeInterval
    let action: AddressBarActionState?
    let actionHandler: (AddressBarAction) -> Void

    @FocusState.Binding
    var isFocused: Bool

    // MARK: - ViewModel

    @StateObject
    private var viewModel: AddressBarViewModel

    // MARK: - Local State (Animation)

    @State
    private var focusPhase: AddressBarFocusPhase = .idle

    @State
    private var focusAnimationTask: Task<Void, Never>? = nil

    @State
    private var animatedBorderScale: CGFloat = 1.5

    // MARK: - Initialization

    init(endpointURL: String,
         securityIndicator: AddressBarSecurityIndicatorState? = nil,
         qualityIndicator: AddressBarQualityIndicatorState? = nil,
         rtt: TimeInterval = 0,
         action: AddressBarActionState? = nil,
         isFocused: FocusState<Bool>.Binding,
         actionHandler: @escaping (AddressBarAction) -> Void) {
        self.endpointURL = endpointURL
        self.securityIndicator = securityIndicator
        self.qualityIndicator = qualityIndicator
        self.rtt = rtt
        self.action = action
        self.actionHandler = actionHandler
        self._isFocused = isFocused
        self._viewModel = StateObject(wrappedValue: AddressBarViewModel(initialURL: endpointURL))
    }

    // MARK: - Body

    var body: some View {
        let radiusSize: CGFloat = (14 + (12 * 2)) / 2

        ZStack {
            mainContent(radiusSize: radiusSize)
            indicatorOverlay
        }
        .detachedOverlay(role: .normalWindow(attachTo: .down)) {
            candidateOverlay
        }
        .zIndex(4)
    }

    // MARK: - View Components

    @ViewBuilder
    private func mainContent(radiusSize: CGFloat) -> some View {
        ZStack {
            labelView
            textFieldView
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .background(.white.opacity(focusPhase.isFocused ? 0.8 : 0.6))
        .overlay(alignment: .bottom) {
            if !focusPhase.isFocused, let action = self.action {
                AddressBarProgressIndicator(progress: action.progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radiusSize))
        .with {
            if #available(macOS 26.0, iOS 26.0, *) {
                $0.glassEffect(.regular.tint(.gray.opacity(0.05)).interactive(true), in: .rect(cornerRadius: radiusSize))
            } else {
                $0.background(.ultraThinMaterial)
            }
        }
        .overlay {
            focusBorder(radiusSize: radiusSize)
        }
        .onTapGesture {
            isFocused = true
        }
        .onChange(of: isFocused) { _, newValue in
            handleFocusChange(newValue)
        }
    }

    @ViewBuilder
    private var labelView: some View {
        HStack(spacing: 0) {
            if let action = self.action {
                HStack(spacing: 0) {
                    Text("\(action.label) - ")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(endpointURL)
                        .font(.system(size: 14))
                        .opacity(focusPhase.labelTextOpacity)
                }
                .opacity(focusPhase.labelTextOpacity)
            } else {
                if endpointURL.isEmpty {
                    Text("호스트 주소를 입력하세요")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .opacity(focusPhase.labelTextOpacity)
                } else {
                    Text(endpointURL)
                        .font(.system(size: 14))
                        .opacity(focusPhase.labelTextOpacity)
                }
            }

            if focusPhase.isFocused {
                Spacer()
            }
        }
        .animation(.linear(duration: 0.2), value: focusPhase.isFocused)
    }

    @ViewBuilder
    private var textFieldView: some View {
        TextField("호스트 주소를 입력하세요", text: $viewModel.draftURL)
#if os(iOS)
            .keyboardType(.URL)
            .submitLabel(.go)
            .textInputAutocapitalization(.never)
#endif
            .opacity(focusPhase.textFieldOpacity)
            .font(.system(size: 14))
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
            .focused($isFocused)
            .animation(.linear(duration: 0.2).delay(0.2), value: focusPhase.isFocused)
            .onSubmit(handleSubmit)
            .onKeyPress(.escape, action: handleEscape)
            .onKeyPress(.downArrow) {
                viewModel.moveFocus(.down)
                return .handled
            }
            .onKeyPress(.upArrow) {
                viewModel.moveFocus(.up)
                return .handled
            }
    }

    @ViewBuilder
    private func focusBorder(radiusSize: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radiusSize)
            .fill(.clear)
#if os(macOS)
            .strokeBorder(
                Color(nsColor: .keyboardFocusIndicatorColor)
                    .opacity(focusPhase.isFocused ? 1 : 0.001),
                lineWidth: 4
            )
#else
            .strokeBorder(
                Color.accentColor
                    .opacity(focusPhase.isFocused ? 1 : 0.001),
                lineWidth: 4
            )
#endif
            .animation(.easeInOut(duration: 0.3), value: focusPhase.isFocused)
            .scaleEffect(animatedBorderScale)
    }

    @ViewBuilder
    private var indicatorOverlay: some View {
        HStack {
            if let securityIndicator = self.securityIndicator {
                AddressBarSecurityIndicator(state: securityIndicator)
            }
            Spacer()
            AddressBarDegradationIndicator(state: .hardwareDecoderUnavailable)
            if let qualityIndicator = self.qualityIndicator {
                AddressBarQualityIndicator(state: qualityIndicator, rtt: rtt)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .opacity(focusPhase.indicatorOpacity)
    }

    @ViewBuilder
    private var candidateOverlay: some View {
        if focusPhase.isFocused, !viewModel.candidates.isEmpty {
            AddressBarCandidateBox(
                candidates: viewModel.candidates,
                focusedIndex: viewModel.candidateFocusIndex,
                onHoverIndex: { index, isHovering in
                    viewModel.updateHoverIndex(index, isHovering: isHovering)
                },
                onSelectIndex: { index in
                    handleCandidateSelection(at: index)
                }
            )
        }
    }

    // MARK: - Event Handlers

    private func handleFocusChange(_ newValue: Bool) {
        // 기존 애니메이션 취소
        focusAnimationTask?.cancel()

        if newValue {
            startFocusInAnimation()
        } else {
            startFocusOutAnimation()
        }
    }

    private func startFocusInAnimation() {
        focusPhase = .focusingIn
        animatedBorderScale = 1.5

        withAnimation(.easeOut(duration: 0.2)) {
            animatedBorderScale = 1.0
        }

        focusAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, focusPhase == .focusingIn else { return }
            focusPhase = .editing
        }
    }

    private func startFocusOutAnimation() {
        focusPhase = .focusingOut

        focusAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, focusPhase == .focusingOut else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                focusPhase = .idle
            }
        }
    }

    private func handleSubmit() {
        isFocused = false

        if let selectedCandidate = viewModel.selectedCandidate() {
            actionHandler(.submit(selectedCandidate))
            return
        }

        let trimmed = viewModel.draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionHandler(.cancel)
            return
        }

        actionHandler(.submit(.quickConnect(endpointURL: trimmed)))
    }

    private func handleEscape() -> KeyPress.Result {
        isFocused = false
        actionHandler(.cancel)
        return .handled
    }

    private func handleCandidateSelection(at index: Int) {
        if let candidate = viewModel.selectCandidate(at: index) {
            isFocused = false
            if candidate.endpointURL == endpointURL {
                actionHandler(.cancel)
            } else {
                actionHandler(.submit(candidate))
            }
        }
    }
}

// MARK: - Preview

private struct AddressBarWithProgressPreviewContainer: View {
    @FocusState private var isFocused: Bool
    @State private var progress: Double = 0.0

    private var action: AddressBarActionState? {
        .fileTransfer(progress: progress)
    }

    var body: some View {
        VStack(spacing: 20) {
            AddressBar(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .neutral,
                qualityIndicator: .good,
                rtt: 0.015,
                action: action,
                isFocused: $isFocused
            ) { action in
                print("Action:", action)
            }

            Text("Progress: \(Int(progress * 100))%")
                .font(.caption)

            HStack(spacing: 12) {
                Button("0%") { progress = 0.0 }
                Button("25%") { progress = 0.25 }
                Button("50%") { progress = 0.5 }
                Button("75%") { progress = 0.75 }
                Button("100%") { progress = 1.0 }
            }

            HStack(spacing: 12) {
                Button("+10%") { progress = min(1.0, progress + 0.1) }
                Button("-10%") { progress = max(0.0, progress - 0.1) }
            }
        }
        .padding(32)
    }
}

private struct AddressBarPreviewContainer: View {
    @FocusState
    private var isFocused: Bool

    let endpointURL: String
    let securityIndicator: AddressBarSecurityIndicatorState?
    let qualityIndicator: AddressBarQualityIndicatorState?
    let action: AddressBarActionState?

    var body: some View {
        AddressBar(
            endpointURL: endpointURL,
            securityIndicator: securityIndicator,
            qualityIndicator: qualityIndicator,
            rtt: 0,
            action: action,
            isFocused: $isFocused
        ) { action in
            print("Action:", action)
        }
    }
}

#Preview("AddressBar with Progress") {
    AddressBarWithProgressPreviewContainer()
        .frame(width: 500, height: 300)
}

#Preview {
    VStack {
        VStack() {
            AddressBarPreviewContainer(
                endpointURL: "",
                securityIndicator: nil,
                qualityIndicator: nil,
                action: nil
            )

            Spacer()
        }
        .zIndex(4)
        .padding(32)
    }
    .frame(minWidth: 400, minHeight: 400)
    .padding(32)
    .background(.white.opacity(0.5))
}
