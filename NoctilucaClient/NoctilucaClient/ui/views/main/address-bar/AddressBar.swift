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

struct AddressBar: View {
    private enum MoveCommandDirection {
        case up
        case down
    }
    
    let endpointURL: String
    let contacts: [ContactItem]
    
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
         contacts: [ContactItem] = [],
         isFocused: FocusState<Bool>.Binding,
         submitHandler: @escaping (EndpointKind?) -> Void) {
        self.endpointURL = endpointURL
        self._draftURL = .init(initialValue: endpointURL)
        self.contacts = contacts
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
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.tint)
                            .frame(width: proxy.size.width * action.progress, height: 4)
                            .offset(y: proxy.size.height - 4)
                    }
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
        contacts.map { item in
            "\(item.id.uuidString):\(item.displayName):\(item.endpointURL)"
        }
    }
}

private struct AddressBarPreviewContainer: View {
    @FocusState
    private var isFocused: Bool

    let endpointURL: String
    let securityIndicator: AddressBarSecurityIndicatorState?
    let qualityIndicator: AddressBarQualityIndicatorState?
    let action: AddressBarActionState?
    let contacts: [ContactItem]

    var body: some View {
        AddressBar(
            endpointURL: endpointURL,
            securityIndicator: securityIndicator,
            qualityIndicator: qualityIndicator,
            rtt: 0,
            action: action,
            contacts: contacts,
            isFocused: $isFocused
        ) { action in
            print(action as Any)
        }
    }
}

#Preview {
    VStack {
        VStack() {
            AddressBarPreviewContainer(
                endpointURL: "",
                securityIndicator: nil,
                qualityIndicator: nil,
                action: nil,
                contacts: []
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
