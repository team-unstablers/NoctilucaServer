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

enum AddressBarDegradationIndicatorState {
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

struct AddressBarSecurityIndicator: View {
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
        VStack {
            iconView
        }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    // let offsetX = -(tooltipSize.width / 2) + (proxy.size.width / 2)
                    if shouldDisplayTooltip {
                        VStack(alignment: .leading, spacing: 0) {
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
                        .fixedSize()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .clipped()
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: 0, y: 26)
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { geom in
                            self.tooltipSize = geom
                        }
                    }
                }
            }
            .onHover { hoverState in
                shouldDisplayTooltip = hoverState
            }
    }
}

struct AddressBarQualityIndicator: View {
    let state: AddressBarQualityIndicatorState
    let rtt: TimeInterval
    
    @State
    var shouldDisplayTooltip = false
    
    @State
    var tooltipSize: CGSize = .zero
    
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
    
    
    /*
    @ViewBuilder
    var iconView: some View {
        switch state {
        case .unknown:
            Image(systemName: "smoke.fill")
                .foregroundColor(.black.opacity(0.7))
        case .poor:
            Image(systemName: "cloud.bolt.rain.fill")
                .foregroundColor(.black.opacity(0.7))
        case .bad:
            Image(systemName: "cloud.fill")
                .foregroundColor(.black.opacity(0.7))
        case .good:
            Image(systemName: "sun.min.fill")
                .foregroundColor(.black.opacity(0.7))
        case .excellent:
            Image(systemName: "sun.max.fill")
                .foregroundColor(.black.opacity(0.7))
        }
    }
     */
    
    var body: some View {
        VStack {
            iconView
        }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    let offsetX = -(tooltipSize.width) + (proxy.size.width)
                    if shouldDisplayTooltip {
                        VStack(alignment: .leading, spacing: 0) {
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
                        .fixedSize()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .clipped()
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: offsetX, y: 26)
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { geom in
                            self.tooltipSize = geom
                        }
                    }
                }
            }
            .onHover { hoverState in
                shouldDisplayTooltip = hoverState
            }
    }
}

struct AddressBarDegradationIndicator: View {
    let state: AddressBarDegradationIndicatorState
    
    @State
    var shouldDisplayTooltip = false
    
    @State
    var tooltipSize: CGSize = .zero
    
    var body: some View {
        VStack {
            Image(systemName: "cloud.bolt.rain.fill")
                .foregroundColor(.black.opacity(0.7))
        }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    let offsetX = -(tooltipSize.width) + (proxy.size.width)
                    if shouldDisplayTooltip {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("하드웨어 가속을 사용할 수 없다고 보고받음")
                                .font(.system(size: 12))
                                .bold()
                                .padding(.bottom, 4)
                            
                            Text("서버로부터 화면 데이터 압축에 하드웨어 가속을 사용할 수 없다고 보고받았습니다.\n동영상 인코딩 세션이 동시에 너무 많이 열려있는 경우 이 문제가 발생할 수 있습니다.\n\n소프트웨어 방식으로 압축을 시도하고 있기 때문에, 서버의 컴퓨팅 성능이 상당히 저하될 수 있습니다.")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.leading)
                        }
                        .fixedSize()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .clipped()
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: offsetX, y: 26)
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { geom in
                            self.tooltipSize = geom
                        }
                    }
                }
            }
            .onHover { hoverState in
                shouldDisplayTooltip = hoverState
            }
    }
}

struct AddressBar: View {
    let endpointURL: String
    
    let securityIndicator: AddressBarSecurityIndicatorState?
    
    let qualityIndicator: AddressBarQualityIndicatorState?
    let rtt: TimeInterval
    
    let action: AddressBarActionState?
    
    let submitHandler: (String) -> Void
    
    init(endpointURL: String,
         securityIndicator: AddressBarSecurityIndicatorState? = nil,
         qualityIndicator: AddressBarQualityIndicatorState? = nil,
         rtt: TimeInterval = 0,
         action: AddressBarActionState? = nil,
         submitHandler: @escaping (String) -> Void) {
        self.endpointURL = endpointURL
        self._draftURL = .init(initialValue: endpointURL)
        self.securityIndicator = securityIndicator
        self.qualityIndicator = qualityIndicator
        self.rtt = rtt
        self.action = action
        self.submitHandler = submitHandler
    }
    
    
    @State
    var draftURL: String = "private-resource-02.internal.contoso.com"
    
    @FocusState
    var isFocused: Bool
    
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
                    .opacity(textFieldOpacity)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    .focused($isFocused)
                    .animation(.linear(duration: 0.2).delay(0.2), value: isFocused)
                    .onSubmit {
                        isFocused = false
                        
                        self.submitHandler(draftURL)
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
            .glassEffect(.regular.tint(.clear).interactive(isFocused), in: .rect(cornerRadius: radiusSize))
            .overlay {
                RoundedRectangle(cornerRadius: radiusSize)
                    .fill(.clear)
                    .strokeBorder(
                        // 시스템 포커스 색상 사용
                        Color(nsColor: .keyboardFocusIndicatorColor)
                            .opacity(isFocused ? 1 : 0.001), // 포커스 없으면 투명
                        lineWidth: 4 // 빛번짐 느낌을 위해 약간 두껍게
                    )
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
        .zIndex(4)
    }
}

#Preview {
    VStack {
        VStack {
            AddressBar(
                endpointURL: "",
            ) { _ in
                
            }
        }
        .zIndex(4)
        .padding(32)

        VStack {
            Text("AddressBar(securityIndicator: .trustable, qualityIndicator: .excellent)")
            AddressBar(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .trustable,
                qualityIndicator: .excellent,
                action: .fileTransfer(progress: 0.5)
            ) { _ in
                
            }
        }
        .zIndex(3)
        .padding(.bottom, 32)
        
        VStack {
            Text("AddressBar(securityIndicator: .dangerous, qualityIndicator: .poor)")
            AddressBar(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .dangerous,
                qualityIndicator: .poor
            ) { _ in
                
            }
        }
        .zIndex(2)
        .padding(.bottom, 32)
        
        VStack {
            Text("AddressBar(securityIndicator: .neutral, qualityIndicator: .good)")
            AddressBar(
                endpointURL: "internal02.contoso.com",
                securityIndicator: .neutral,
                qualityIndicator: .good
            ) { _ in
            }
        }
        .zIndex(1)
        .padding(.bottom, 32)
        
        Spacer()
        Button("test") {}
    }
    .frame(minWidth: 400, minHeight: 400)
    .padding(32)
    .background(.white.opacity(0.5))
}


