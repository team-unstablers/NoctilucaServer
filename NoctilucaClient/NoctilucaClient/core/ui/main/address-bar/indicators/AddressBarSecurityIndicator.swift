//
//  AddressBarSecurityIndicator.swift
//  NoctilucaClient
//

import SwiftUI

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
            return String(localized: "main.address_bar.security.neutral.title", defaultValue: "암호화된 연결")
        case .dangerous:
            return String(localized: "main.address_bar.security.dangerous.title", defaultValue: "안전하지 않은 연결")
        case .trustable:
            return String(localized: "main.address_bar.security.trustable.title", defaultValue: "안전한 연결")
        }
    }

    var tooltipText: String {
        switch state {
        case .neutral:
            return String(localized: "main.address_bar.security.neutral.description", defaultValue: "이 호스트는 자가 서명 인증서를 사용하여 암호화된 연결을 제공하고 있습니다.")
        case .dangerous:
            return String(localized: "main.address_bar.security.dangerous.description", defaultValue: "이 호스트는 macOS의 트러스트 스토어에서 신뢰가 거부된 인증서를 사용하고 있습니다.\n원격 제어 세션의 내용을 제 3자가 도청하거나 변조할 위험이 있습니다.")
        case .trustable:
            return String(localized: "main.address_bar.security.trustable.description", defaultValue: "이 호스트는 macOS의 트러스트 스토어에서 신뢰하는 인증서를 사용하여 암호화 연결을 제공하고 있습니다.")
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

            Text(String(localized: "main.address_bar.security.icon_hint", defaultValue: "이 아이콘을 누르면 서버의 인증서 정보를 확인할 수 있습니다."))
                .font(.system(size: 11))
        }
    }
}

#Preview("Security Indicator - Neutral") {
    AddressBarSecurityIndicator(state: .neutral)
        .padding()
}

#Preview("Security Indicator - Dangerous") {
    AddressBarSecurityIndicator(state: .dangerous)
        .padding()
}

#Preview("Security Indicator - Trustable") {
    AddressBarSecurityIndicator(state: .trustable)
        .padding()
}
