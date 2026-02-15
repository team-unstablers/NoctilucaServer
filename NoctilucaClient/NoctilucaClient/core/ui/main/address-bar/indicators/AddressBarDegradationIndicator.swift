//
//  AddressBarDegradationIndicator.swift
//  NoctilucaClient
//

import SwiftUI

struct AddressBarDegradationIndicator: View {
    let state: AddressBarDegradationIndicatorState

    private var reasonText: String {
        var parts: [String] = []

        if state.reasons.contains(.poorNetworkThroughput) {
            parts.append(String(localized: "main.address_bar.degradation.reason.network", defaultValue: "네트워크 대역폭이 부족합니다."))
        }
        if state.reasons.contains(.poorClientDecodingPerformance) {
            parts.append(String(localized: "main.address_bar.degradation.reason.decoding", defaultValue: "디코딩 성능이 부족합니다."))
        }
        if state.reasons.contains(.poorServerEncodingPerformance) {
            parts.append(String(localized: "main.address_bar.degradation.reason.encoding", defaultValue: "서버의 인코딩 성능이 부족합니다."))
        }

        if parts.isEmpty {
            return String(localized: "main.address_bar.degradation.reason.unknown", defaultValue: "알 수 없는 이유로 화면 품질이 조정되었습니다.")
        }

        return parts.joined(separator: "\n")
    }

    private var adjustmentText: String {
        var parts: [String] = []

        if state.types.contains(.resolution) {
            parts.append(String(localized: "main.address_bar.degradation.adjustment.resolution", defaultValue: "해상도 낮춤"))
        }
        if state.types.contains(.framerate) {
            parts.append(String(localized: "main.address_bar.degradation.adjustment.framerate", defaultValue: "프레임레이트 낮춤"))
        }
        if state.types.contains(.bitrate) {
            parts.append(String(localized: "main.address_bar.degradation.adjustment.bitrate", defaultValue: "비트레이트 낮춤"))
        }
        if state.types.contains(.encodingEfficiency) {
            parts.append(String(localized: "main.address_bar.degradation.adjustment.encoding_efficiency", defaultValue: "인코딩 효율 우선 모드"))
        }

        if parts.isEmpty { return "" }
        return String(localized: "main.address_bar.degradation.adjustment_prefix", defaultValue: "조정 사항: ") + parts.joined(separator: ", ")
    }

    private var additionalInfoText: String? {
        if state.additionalInfo.contains(.hardwareEncoderUnavailable) {
            return String(localized: "main.address_bar.degradation.hw_encoder_unavailable", defaultValue: "서버가 하드웨어 인코더를 사용할 수 없는 상태입니다.\n소프트웨어 인코딩으로 인해 성능이 저하될 수 있습니다.")
        }
        return nil
    }

    var body: some View {
        AddressBarIndicatorView {
            Image(systemName: "cloud.bolt.rain.fill")
                .foregroundColor(.black.opacity(0.7))
        } tooltip: {
            Text(String(localized: "main.address_bar.degradation.title", defaultValue: "화면 품질이 저하되었습니다"))
                .font(.system(size: 12))
                .bold()
                .padding(.bottom, 4)

            Text(reasonText)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)

            if !adjustmentText.isEmpty {
                Text(adjustmentText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            if let additionalInfoText {
                Text(additionalInfoText)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview("Degradation - Network") {
    AddressBarDegradationIndicator(state: .init(
        reasons: [.poorNetworkThroughput],
        types: [.bitrate, .framerate],
        additionalInfo: []
    ))
    .padding()
}

#Preview("Degradation - HW Encoder Unavailable") {
    AddressBarDegradationIndicator(state: .init(
        reasons: [.poorServerEncodingPerformance],
        types: [.bitrate],
        additionalInfo: [.hardwareEncoderUnavailable]
    ))
    .padding()
}
