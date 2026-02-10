//
//  ServerIdentityValidationSheetView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/10/26.
//

import Foundation
import SwiftUI

import Security

#if os(macOS)
import SecurityInterface
#endif

import SiriusKitClient

#if os(macOS)
// FIXME: 소스 코드 분리해야 함
struct NOCCertificateView: NSViewRepresentable {
    let certificate: SecCertificate
    
    func makeNSView(context: Context) -> SFCertificateView {
        let certView = SFCertificateView()
        certView.setCertificate(certificate)
        certView.setDetailsDisclosed(true)
        
        return certView
    }
    
    func updateNSView(_ nsView: SFCertificateView, context: Context) {
        // No update needed
    }
}
#endif

enum ServerIdentityValidationSheetViewExtraInfo {
    case none
    
    /// 서버에서 제시한 인증서 지문이 known_hosts의 레코드와 일치하지 않습니다.
    case fingerprintMismatch(expectedFingerprint: String, actualFingerprint: String)
}

struct ServerIdentityValidationSheetView: View {
    let hostname: String
    let certificate: SecCertificate
    let extraInfo: ServerIdentityValidationSheetViewExtraInfo
    
    @ViewBuilder
    var header: some View {
        switch extraInfo {
        case .fingerprintMismatch(let expectedFingerprint, let actualFingerprint):
            HStack(spacing: 0) {
                Text("위험: ")
                    .foregroundStyle(.red)
                Text("서버 인증서 지문이 일치하지 않습니다!")
            }
                .font(.headline)
                .padding(.bottom, 4)
                .foregroundStyle(.primary)
            Text("`\(hostname)`에서 인증서를 제시했지만, 인증서 지문이 저번에 접속했을 때와 다릅니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            
            // TODO: accordion: "지문 값 상세"
            VStack(alignment: .leading) {
                Text("기대한 지문 값: `\(expectedFingerprint)`")
                Text("실제 지문 값: `\(actualFingerprint)`")
            }
                .padding(.bottom, 12)
            
            // TODO: accordion: "이 메시지는 왜 표시되나요?"
            VStack(alignment: .leading) {
                Text("이 오류는 다음과 같은 경우에 발생할 수 있습니다:")
                
                Text("• 서버 관리자가 인증서를 교체하였습니다.")
                Text("• 중간자 공격(MITM)의 가능성이 있습니다: 누군가가 악의적인 목적으로 통신 내용을 훔쳐보거나 변조하려 할 수도 있습니다.")
            }
            
            
        case .none:
            Text("유효하지 않은 서버 인증서")
                .font(.headline)
                .padding(.bottom, 4)
                .foregroundStyle(.primary)
            Text("`\(hostname)`은 다음과 같은 인증서를 제시하였습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            
            // TODO: accordion: "인증서 상세 정보"
            // TODO: 인증서 체인을 보여줘야 하는거 아닐까? :/
            VStack {
                ScrollView {
                    NOCCertificateView(certificate: certificate)
                }
                .frame(height: 300)
            }
                .background(.white)
                .border(Color.gray.opacity(0.5), width: 1)
                .padding(.bottom, 12)
            
            
            VStack {
                Picker(selection: .constant(0)) {
                    Text("이번 한 번만 이 인증서를 신뢰합니다").tag(0)
                    Text("항상 이 인증서를 신뢰합니다").tag(1)
                } label: {
                    Text("신뢰 옵션")
                }
            }
            .padding(.bottom, 12)


            HStack {
                Button("연결 끊기", role: .cancel) {
                    
                }
                Spacer()
                .keyboardShortcut(.escape)
                
                
                Button("계속 진행하기", role: .compatibleConfirm) {
                }
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

#if DEBUG

/// 키체인에서 아무 인증서나 적당히 고릅니다
func pickAnyCertificate() -> SecCertificate? {
    let result = SRKeychain.shared.queryItem(by: "Noctiluca Server: self-signed server identity (cheese-mbpr14.local)", clazz: .certificate)
    guard let item = try? result.get() else {
        return nil
    }
    
    return item as! SecCertificate
}


#Preview {
    let certificate = pickAnyCertificate()
    
    if let certificate {
        ServerIdentityValidationSheetView(
            hostname: "resource01.internal.contoso.com",
            certificate: certificate,
            extraInfo: .fingerprintMismatch(expectedFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B", actualFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B")
        )
        .fixedSize()
    } else {
        Text("FIXME: certificate not available")
    }
    
}
#endif
    
