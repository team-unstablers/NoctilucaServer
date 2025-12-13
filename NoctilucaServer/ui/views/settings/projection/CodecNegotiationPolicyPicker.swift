//
//  CodecNegotiationPolicyPicker.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import SwiftUI

struct CodecNegotiationPolicyPicker: View {
    var body: some View {
        Picker(selection: .constant(CodecNegotiationPolicy.balanced)) {
            VStack(alignment: .leading) {
                Text("균형 잡힌 결정 내리기 **(권장)**")
                Text("클라이언트의 요청을 존중하면서 서버의 성능과 안정성을 해치지 않는 범위 내에서 최적의 코덱을 선택합니다.\n서버가 지원할 수 없는 명세의 코덱이 요청되었을 때에는 Noctilcua Server가 적절하다고 판단하는 코덱으로 임의 대체합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .tag(CodecNegotiationPolicy.balanced)

            VStack(alignment: .leading) {
                Text("서버 설정을 우선으로")
                Text("클라이언트의 요청을 완전히 무시하고 서버의 코덱 설정을 우선시합니다.\n클라이언트가 지원하지 않는 코덱이 설정되어 있을 경우 연결에 실패할 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .tag(CodecNegotiationPolicy.overrideFromServer)
        } label: {
            Text("코덱 협상 정책")
            Text("클라이언트와의 코덱 협상 정책을 설정합니다.")
            
        }
        .pickerStyle(.inline)
        
    }
}
