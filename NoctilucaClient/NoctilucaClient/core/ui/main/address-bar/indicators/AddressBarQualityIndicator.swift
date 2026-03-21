//
//  AddressBarQualityIndicator.swift
//  NoctilucaClient
//

import SwiftUI

struct AddressBarQualityIndicator: View {
    @Environment(\.colorScheme)
    var colorScheme

    let state: AddressBarQualityIndicatorState
    let rtt: TimeInterval
    
    var primaryColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var tooltipTitle: String {
        switch state {
        case .unknown:
            return String(localized: "quality.title.unknown", defaultValue: "연결 품질 알 수 없음")
        case .poor:
            return String(localized: "quality.title.poor", defaultValue: "매우 낮은 연결 품질")
        case .bad:
            return String(localized: "quality.title.bad", defaultValue: "낮은 연결 품질")
        case .good:
            return String(localized: "quality.title.good", defaultValue: "양호한 연결 품질")
        case .excellent:
            return String(localized: "quality.title.excellent", defaultValue: "우수한 연결 품질")
        }
    }

    var tooltipText: String {
        switch state {
        case .unknown:
            return String(localized: "quality.desc.unknown", defaultValue: "서버와의 연결 품질을 알 수 없습니다.")
        case .poor:
            return String(localized: "quality.desc.poor", defaultValue: "서버와의 연결 품질이 매우 낮습니다. 원격 제어 세션이 원활하지 않을 수 있습니다.")
        case .bad:
            return String(localized: "quality.desc.bad", defaultValue: "서버와의 연결 품질이 낮습니다. 원격 제어 세션이 다소 원활하지 않을 수 있습니다.")
        case .good:
            return String(localized: "quality.desc.good", defaultValue: "서버와의 연결 품질이 양호합니다.")
        case .excellent:
            return String(localized: "quality.desc.excellent", defaultValue: "서버와의 연결 품질이 우수합니다.")
        }
    }

    @ViewBuilder
    var iconView: some View {
        switch state {
        case .unknown:
            Image(systemName: "cellularbars", variableValue: 0.0)
                .foregroundColor(primaryColor.opacity(0.7))
        case .poor:
            Image(systemName: "cellularbars", variableValue: 0.25)
                .foregroundColor(primaryColor.opacity(0.7))
        case .bad:
            Image(systemName: "cellularbars", variableValue: 0.5)
                .foregroundColor(primaryColor.opacity(0.7))
        case .good:
            Image(systemName: "cellularbars", variableValue: 0.75)
                .foregroundColor(primaryColor.opacity(0.7))
        case .excellent:
            Image(systemName: "cellularbars", variableValue: 1)
                .foregroundColor(primaryColor.opacity(0.7))
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

#Preview("Quality Indicator - Unknown") {
    AddressBarQualityIndicator(state: .unknown, rtt: 0)
        .padding()
}

#Preview("Quality Indicator - Poor") {
    AddressBarQualityIndicator(state: .poor, rtt: 0.5)
        .padding()
}

#Preview("Quality Indicator - Excellent") {
    AddressBarQualityIndicator(state: .excellent, rtt: 0.015)
        .padding()
}
