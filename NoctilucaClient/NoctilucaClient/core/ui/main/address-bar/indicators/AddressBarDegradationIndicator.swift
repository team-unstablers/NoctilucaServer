//
//  AddressBarDegradationIndicator.swift
//  NoctilucaClient
//

import SwiftUI

struct AddressBarDegradationIndicator: View {
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

#Preview("Degradation Indicator") {
    AddressBarDegradationIndicator(state: .hardwareDecoderUnavailable)
        .padding()
}
