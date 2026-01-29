//
//  EndpointURLField.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

enum AddressBarSecurityIndicatorState {
    case neutral
    case dangerous
    case trustable
}

enum AddressBarQualityIndicatorState {
    case unknown
    case poor
    case bad
    case good
    case excellent
}

private enum AddressBarDegradationIndicatorState {
    case none
    
    case hardwareEncoderUnavailable
    case hardwareDecoderUnavailable
}

enum AddressBarActionState {
    case connecting(progress: Double)
    case fileTransfer(progress: Double)
    
    var label: String {
        switch self {
        case .connecting(let progress):
            return "연결 중"
        case .fileTransfer(let progress):
            return "파일 전송 중"
        }
    }
    
    var progress: Double {
        switch self {
        case .connecting(let progress):
            return progress
        case .fileTransfer(let progress):
            return progress
        }
    }
}

private struct AddressBarSecurityIndicator: View {
    let state: AddressBarSecurityIndicatorState
    
    @State
    var shouldDisplayTooltip = false
    
    @State
    var tooltipSize: CGSize = .zero
    
    @ViewBuilder
    var iconView: some View {
        switch state {
        case .neutral:
            Image(systemName: "lock.fill")
                .foregroundColor(.black.opacity(0.6))
        case .dangerous:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red.mix(with: .black, by: 0.2))
        case .trustable:
            Image(systemName: "lock.fill")
                .foregroundColor(.green.mix(with: .black, by: 0.2))
        }
    }
    
    var tooltipTitle: String {
        switch state {
        case .neutral:
            return "암호화된 연결"
        case .dangerous:
            return "안전하지 않은 연결"
        case .trustable:
            return "안전한 연결"
        }
    }
    
    var tooltipText: String {
        switch state {
        case .neutral:
            return "이 호스트는 자가 서명 인증서를 사용하여 암호화된 연결을 제공하고 있습니다."
        case .dangerous:
            return "이 호스트는 macOS의 트러스트 스토어에서 신뢰가 거부된 인증서를 사용하고 있습니다.\n원격 제어 세션의 내용을 제 3자가 도청하거나 변조할 위험이 있습니다."
        case .trustable:
            return "이 호스트는 macOS의 트러스트 스토어에서 신뢰하는 인증서를 사용하여 암호화 연결을 제공하고 있습니다."
        }
    }
    
    var body: some View {
        AddressBarIndicatorView {
            iconView
        } tooltip: {
            Text(tooltipTitle)
                .font(.system(size: 12))
                .bold()
                .padding(.bottom, 4)
            
            Text(tooltipText)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
                .padding(.bottom, 4)
            
            Text("이 아이콘을 누르면 서버의 인증서 정보를 확인할 수 있습니다.")
                .font(.system(size: 11))
        }
    }
}

private struct AddressBarQualityIndicator: View {
    let state: AddressBarQualityIndicatorState
    let rtt: TimeInterval

    var tooltipTitle: String {
        switch state {
        case .unknown:
            return "연결 품질 알 수 없음"
        case .poor:
            return "매우 낮은 연결 품질"
        case .bad:
            return "낮은 연결 품질"
        case .good:
            return "양호한 연결 품질"
        case .excellent:
            return "우수한 연결 품질"
        }
    }
    
    var tooltipText: String {
        switch state {
        case .unknown:
            return "서버와의 연결 품질을 알 수 없습니다."
        case .poor:
            return "서버와의 연결 품질이 매우 낮습니다. 원격 제어 세션이 원활하지 않을 수 있습니다."
        case .bad:
            return "서버와의 연결 품질이 낮습니다. 원격 제어 세션이 다소 원활하지 않을 수 있습니다."
        case .good:
            return "서버와의 연결 품질이 양호합니다."
        case .excellent:
            return "서버와의 연결 품질이 우수합니다."
        }
    }
    
    @ViewBuilder
    var iconView: some View {
        switch state {
        case .unknown:
            Image(systemName: "cellularbars", variableValue: 0.0)
                .foregroundColor(.black.opacity(0.7))
        case .poor:
            Image(systemName: "cellularbars", variableValue: 0.25)
                .foregroundColor(.black.opacity(0.7))
        case .bad:
            Image(systemName: "cellularbars", variableValue: 0.5)
                .foregroundColor(.black.opacity(0.7))
        case .good:
            Image(systemName: "cellularbars", variableValue: 0.75)
                .foregroundColor(.black.opacity(0.7))
        case .excellent:
            Image(systemName: "cellularbars", variableValue: 1)
                .foregroundColor(.black.opacity(0.7))
        }
    }
    
    var body: some View {
        AddressBarIndicatorView {
            iconView
        } tooltip: {
            Text(tooltipTitle)
                .font(.system(size: 12))
                .bold()
                .padding(.bottom, 4)
            
            Text(tooltipText)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
                .padding(.bottom, 4)
            
            // %.1fms 형식으로 표시
            Text("ping: \(String(format: "%.1f", rtt * 1000))ms")
                .font(.system(size: 11))
        }
    }
}

private struct AddressBarDegradationIndicator: View {
    let state: AddressBarDegradationIndicatorState

    var body: some View {
        AddressBarIndicatorView {
            Image(systemName: "cloud.bolt.rain.fill")
                .foregroundColor(.black.opacity(0.7))
        } tooltip: {
            // FIXME: 디그레이션 이유를 받아야 함
            Text("하드웨어 가속을 사용할 수 없다고 보고받음")
                .font(.system(size: 12))
                .bold()
                .padding(.bottom, 4)
            
            Text("서버로부터 화면 데이터 압축에 하드웨어 가속을 사용할 수 없다고 보고받았습니다.\n동영상 인코딩 세션이 동시에 너무 많이 열려있는 경우 이 문제가 발생할 수 있습니다.\n\n소프트웨어 방식으로 압축을 시도하고 있기 때문에, 서버의 컴퓨팅 성능이 상당히 저하될 수 있습니다.")
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
        }
    }
}

private struct AddressBarProgressIndicator: View {
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

struct AddressBar: View {
    private enum MoveCommandDirection {
        case up
        case down
    }

    let endpointURL: String

    @ObservedObject
    private var contactsStore = ContactsStore.shared

    let securityIndicator: AddressBarSecurityIndicatorState?
    
    let qualityIndicator: AddressBarQualityIndicatorState?
    let rtt: TimeInterval
    
    let action: AddressBarActionState?
    
    let submitHandler: (EndpointKind?) -> Void
    @FocusState.Binding
    var isFocused: Bool
    
    init(endpointURL: String,
         securityIndicator: AddressBarSecurityIndicatorState? = nil,
         qualityIndicator: AddressBarQualityIndicatorState? = nil,
         rtt: TimeInterval = 0,
         action: AddressBarActionState? = nil,
         isFocused: FocusState<Bool>.Binding,
         submitHandler: @escaping (EndpointKind?) -> Void) {
        self.endpointURL = endpointURL
        self._draftURL = .init(initialValue: endpointURL)
        self.securityIndicator = securityIndicator
        self.qualityIndicator = qualityIndicator
        self.rtt = rtt
        self.action = action
        self.submitHandler = submitHandler
        self._isFocused = isFocused
    }
    
    
    @State
    var draftURL: String = "private-resource-02.internal.contoso.com"
    
    @State
    var candidates: [EndpointKind] = []
    
    
    @State
    var candidateFocusIndex: Int? = nil
    
    @State
    var labelAreaOpacity: CGFloat = 1.0
    
    @State
    var labelTextOpacity: CGFloat = 1.0
    
    @State
    var textFieldOpacity: CGFloat = 0.0
    
    @State
    var focusBorderScale: CGFloat = 1.5
    
    var body: some View {
        let radiusSize: CGFloat = (14 + (12 * 2)) / 2
        ZStack {
            ZStack {
                ZStack {
                    HStack(spacing: 0) {
                        if let action = self.action {
                            HStack(spacing: 0) {
                                Text("\(action.label) - ")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Text(endpointURL)
                                    .font(.system(size: 14)) // TODO: dynamic size
                                    .opacity(labelTextOpacity)
                            }
                            .opacity(labelTextOpacity)
                        } else {
                            if endpointURL.isEmpty {
                                Text("호스트 주소를 입력하세요")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .opacity(labelTextOpacity)
                            } else {
                                Text(endpointURL)
                                    .font(.system(size: 14))
                                    .opacity(labelTextOpacity)
                            }
                        }
                        
                        if isFocused {
                            Spacer()
                        }
                    }
                    .animation(.linear(duration: 0.2), value: isFocused)
                }
                
                TextField("호스트 주소를 입력하세요", text: $draftURL)
#if os(iOS)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .textInputAutocapitalization(.never)
#endif
                    .opacity(textFieldOpacity)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    .focused($isFocused)
                    .animation(.linear(duration: 0.2).delay(0.2), value: isFocused)
                    .onSubmit {
                        isFocused = false

                        if let selectedCandidate = self.selectedCandidate() {
                            self.submitCandidate(selectedCandidate)
                            return
                        }

                        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            self.submitHandler(nil)
                            return
                        }

                        self.submitCandidate(.quickConnect(endpointURL: trimmed))
                    }
                    .onKeyPress(.escape) {
                        isFocused = false
                        
                        // FIXME: 이딴 식으로 하지 마세요
                        self.submitHandler(nil)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        self.moveFocus(.down)
                        
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        self.moveFocus(.up)
                        
                        return .handled
                    }
                    .onChange(of: draftURL) { _, newValue in
                        self.candidateFocusIndex = nil
                        updateCandidates(for: newValue)
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(.white.opacity(isFocused ? 0.8 : 0.6))
            .overlay(alignment: .bottom) {
                if !isFocused, let action = self.action {
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
                RoundedRectangle(cornerRadius: radiusSize)
                    .fill(.clear)
#if os(macOS)
                    .strokeBorder(
                        // 시스템 포커스 색상 사용
                        Color(nsColor: .keyboardFocusIndicatorColor)
                            .opacity(isFocused ? 1 : 0.001), // 포커스 없으면 투명
                        lineWidth: 4 // 빛번짐 느낌을 위해 약간 두껍게
                    )
#else
                    .strokeBorder(
                        // 시스템 포커스 색상 사용
                        Color.accentColor
                            .opacity(isFocused ? 1 : 0.001), // 포커스 없으면 투명
                        lineWidth: 4 // 빛번짐 느낌을 위해 약간 두껍게
                    )
#endif
                    .scaleEffect(focusBorderScale)
                    .animation(.easeIn(duration: 0.2), value: isFocused)
            }
            .onTapGesture {
                isFocused = true
            }
            .onChange(of: isFocused) { newValue in
                if (newValue) {
                    focusBorderScale = 1.5
                    labelAreaOpacity = 0.0
                    withAnimation(.easeOut(duration: 0.2)) {
                        focusBorderScale = 1.0
                    } completion: {
                        labelTextOpacity = 0.0
                        textFieldOpacity = 1.0
                    }
                } else {
                    textFieldOpacity = 0.0
                    labelTextOpacity = 1.0
                    withAnimation(.easeOut(duration: 0.2)) {
                        labelAreaOpacity = 1.0
                    } completion: {
                    }
                }
            }
            .onChange(of: contactSignature) { _, _ in
                candidateFocusIndex = nil
                updateCandidates(for: draftURL)
            }
            .onAppear {
                updateCandidates(for: draftURL)
            }
            
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
            .opacity(labelAreaOpacity)
        }
        .detachedOverlay(role: .normalWindow(attachTo: .down)) {
            if isFocused, !candidates.isEmpty {
                AddressBarCandidateBox(
                    candidates: self.candidates,
                    focusedIndex: self.candidateFocusIndex,
                    onHoverIndex: { index, isHovering in
                        self.updateHoverIndex(index, isHovering: isHovering)
                    },
                    onSelectIndex: { index in
                        self.selectCandidate(at: index)
                    }
                )
            }
        }
        .zIndex(4)
    }
    
    private func moveFocus(_ direction: MoveCommandDirection) {
        guard !self.candidates.isEmpty else { return }

        let currentIndex = self.candidateFocusIndex
        let nextIndex: Int?
        
        switch direction {
        case .down:
            if currentIndex == nil {
                nextIndex = 0
            } else {
                nextIndex = min(currentIndex! + 1, candidates.count - 1)
            }
        case .up:
            if currentIndex == nil {
                nextIndex = candidates.count - 1
            } else {
                nextIndex = currentIndex! - 1 >= 0 ? currentIndex! - 1 : nil
            }
        default:
            return
        }
        
        self.candidateFocusIndex = nextIndex
    }

    private func selectedCandidate() -> EndpointKind? {
        guard let index = self.candidateFocusIndex,
              self.candidates.indices.contains(index) else {
            return nil
        }

        return self.candidates[index]
    }

    private func submitCandidate(_ candidate: EndpointKind) {
        if candidate.endpointURL == endpointURL {
            // FIXME: 이딴 식으로 하지 마세요
            self.submitHandler(nil)
            return
        }

        self.submitHandler(candidate)
    }

    private func updateHoverIndex(_ index: Int, isHovering: Bool) {
        guard isHovering else { return }
        guard self.candidates.indices.contains(index) else { return }

        self.candidateFocusIndex = index
    }

    private func selectCandidate(at index: Int) {
        guard self.candidates.indices.contains(index) else { return }

        self.candidateFocusIndex = index
        self.isFocused = false
        self.submitCandidate(self.candidates[index])
    }

    private func updateCandidates(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated: [EndpointKind] = []

        if !trimmed.isEmpty {
            updated.append(.quickConnect(endpointURL: trimmed))
            updated.append(.connect(endpointURL: trimmed))
        }

        let matches = filterContacts(for: trimmed)
        updated.append(contentsOf: matches.map { .contact(item: $0) })

        self.candidates = updated
    }

    private func filterContacts(for query: String) -> [ContactItem] {
        let contacts = contactsStore.contacts
        guard !contacts.isEmpty else { return [] }

        if query.isEmpty {
            return contacts
        }

        return contacts.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.endpointURL.localizedCaseInsensitiveContains(query)
        }
    }

    private var contactSignature: [String] {
        contactsStore.contacts.map { item in
            "\(item.id.uuidString):\(item.displayName):\(item.endpointURL)"
        }
    }
}

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
            ) { _ in }

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
            print(action as Any)
        }
    }
}

#Preview("Progress Indicator") {
    AddressBarProgressIndicatorPreviewContainer()
        .frame(width: 400, height: 200)
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

        /*
        VStack {
            Text("AddressBar(securityIndicator: .trustable, qualityIndicator: .excellent)")
            AddressBarPreviewContainer(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .trustable,
                qualityIndicator: .excellent,
                action: .fileTransfer(progress: 0.5),
                contacts: []
            )
        }
        .zIndex(3)
        .padding(.bottom, 32)
        
        VStack {
            Text("AddressBar(securityIndicator: .dangerous, qualityIndicator: .poor)")
            AddressBarPreviewContainer(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .dangerous,
                qualityIndicator: .poor,
                action: nil,
                contacts: []
            )
        }
        .zIndex(2)
        .padding(.bottom, 32)
        
        VStack {
            Text("AddressBar(securityIndicator: .neutral, qualityIndicator: .good)")
            AddressBarPreviewContainer(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .neutral,
                qualityIndicator: .good,
                action: nil,
                contacts: []
            )
        }
        .zIndex(1)
        .padding(.bottom, 32)
        
        Spacer()
        Button("test") {}
         */
    }
    .frame(minWidth: 400, minHeight: 400)
    .padding(32)
    .background(.white.opacity(0.5))
}
