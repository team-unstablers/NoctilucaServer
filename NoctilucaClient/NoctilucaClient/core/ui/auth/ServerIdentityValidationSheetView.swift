//
//  ServerIdentityValidationSheetView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/10/26.
//

import Foundation
import SwiftUI

import Security

import SiriusKitClient

enum ServerIdentityValidationSheetViewExtraInfo {
    case none

    /// 서버에서 제시한 인증서 지문이 known_hosts의 레코드와 일치하지 않습니다.
    case fingerprintMismatch(expectedFingerprint: String, actualFingerprint: String)
}

enum ServerIdentityValidationTrustDecision {
    case once
    case always
}

enum ServerIdentityValidationAction {
    case disconnect
    case proceed(ServerIdentityValidationTrustDecision)
}


struct ServerIdentityValidationSheetView: View {
    let hostname: String
    let certificate: SecCertificateLike
    let extraInfo: ServerIdentityValidationSheetViewExtraInfo
    let handler: (ServerIdentityValidationAction) -> Void

    @State
    var isCertificateDetailsExpanded: Bool = true

    @State
    var trustDecision: ServerIdentityValidationTrustDecision = .once

    @ViewBuilder
    var header: some View {
        switch extraInfo {
        case .fingerprintMismatch(let expectedFingerprint, let actualFingerprint):
            HStack(spacing: 0) {
                Text("위험: ")
                    .foregroundStyle(.red)
                Text("서버 인증서 지문이 일치하지 않습니다!")
            }
                .font(DeviceKind.current == .mac ? .headline : .subheadline)
                .padding(.bottom, 4)
                .foregroundStyle(.primary)
            Text("`\(hostname)`에서 인증서를 제시했지만, 인증서 지문이 저번에 접속했을 때와 다릅니다.")
                .font(DeviceKind.current == .mac ? .subheadline : .footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text("기대한 지문 값: `\(expectedFingerprint)`")
                    Text("실제 지문 값: `\(actualFingerprint)`")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(DeviceKind.current == .mac ? .callout : .caption)
                .textSelection(.enabled)
            } label: {
                Text("지문 값 상세")
                    .disclosureLabelStyle()
            }
            .padding(.bottom, 12)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text("이 오류는 다음과 같은 경우에 발생할 수 있습니다:")
                    Text("• 서버 관리자가 인증서를 교체하였습니다.")
                    Text("• 중간자 공격(MITM)의 가능성이 있습니다: 누군가가 악의적인 목적으로 통신 내용을 훔쳐보거나 변조하려 할 수도 있습니다.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(DeviceKind.current == .mac ? .callout : .caption)
            } label: {
                Text("이 메시지는 왜 표시되나요?")
                    .disclosureLabelStyle()
            }
            .padding(.bottom, 12)


        case .none:
            Text("유효하지 않은 서버 인증서")
                .font(DeviceKind.current == .mac ? .headline : .subheadline)
                .padding(.bottom, 4)
                .foregroundStyle(.primary)
            Text("`\(hostname)`은 다음과 같은 인증서를 제시하였습니다.")
                .font(DeviceKind.current == .mac ? .subheadline : .footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    var footer: some View {
        switch extraInfo {
        case .none:
            EmptyView()
        case .fingerprintMismatch(_, _):
            Text("계속 진행하면, 지문 정보를 업데이트 하게 됩니다.")
                .padding(.bottom, 12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header

            // TODO: 인증서 체인을 보여줘야 하는거 아닐까? :/
            DisclosureGroup(isExpanded: $isCertificateDetailsExpanded) {
                ScrollView {
                    NOCCertificateView(certificate: certificate)
                }
#if os(macOS)
                .frame(height: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.gray.opacity(0.5), width: 1)
#else
                .padding()
                .border(Color.gray.opacity(0.5), width: 1)
                .padding(.vertical)
#endif
            } label: {
                Text("인증서 상세 정보")
                    .disclosureLabelStyle()
            }
            .padding(.bottom, 12)

            self.footer

            VStack {
                Picker(selection: $trustDecision) {
                    Text("이번 한 번만 이 인증서를 신뢰합니다").tag(ServerIdentityValidationTrustDecision.once)
                    Text("항상 이 인증서를 신뢰합니다").tag(ServerIdentityValidationTrustDecision.always)
                } label: {
                    Text("신뢰 옵션")
                }
            }
            .padding(.bottom, 12)


            HStack {
                Button("연결 끊기", role: .cancel) {
                    handler(.disconnect)
                }
                .keyboardShortcut(.escape)
                .if(DeviceKind.current != .mac) {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        $0.buttonStyle(.glass)
                    } else {
                        $0
                    }
                }

                Spacer()

                Button("계속 진행하기", role: .destructive) {
                    handler(.proceed(trustDecision))
                }
                .if(DeviceKind.current != .mac) {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        $0.buttonStyle(.glassProminent)
                    } else {
                        $0
                    }
                }
            }
        }
        .padding(24)
        .if(DeviceKind.current == .mac) {
            $0.frame(width: 640)
        }
    }
}

private extension View {
    @ViewBuilder
    func disclosureLabelStyle() -> some View {
#if os(iOS)
        self.foregroundStyle(Color(uiColor: UIColor.label))
            .bold()
#else
        self.bold()
#endif
    }
}

#if DEBUG

#if !os(macOS)
struct MockedCertificate: SecCertificateLike {
    var commonName: String
    var notBefore: Date?
    var notAfter: Date?
    var fingerprint: String?
}
#endif

/// 키체인에서 아무 인증서나 적당히 고릅니다
func pickAnyCertificate() -> SecCertificateLike? {
#if os(macOS)
    let result = SRKeychain.shared.queryItem(by: "Noctiluca Server: self-signed server identity (cheese-mbpr14.local)", clazz: .certificate)
    guard let item = try? result.get() else {
        return nil
    }

    return item as! SecCertificate
#else
    return MockedCertificate(
        commonName: "Noctiluca Server: self-signed server identity (cheese-mbpr14.local)",
        notBefore: Date(),
        notAfter: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
        fingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B"
    )
#endif
}


#Preview {
    let certificate = pickAnyCertificate()

    VStack {}
        .dialog(isPresented: .constant(true)) {
            if let certificate {
                ServerIdentityValidationSheetView(
                    hostname: "resource01.internal.contoso.com",
                    certificate: certificate,
                    extraInfo: .fingerprintMismatch(expectedFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B", actualFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B")
                ) { action in
                    print(action)
                }
            } else {
                Text("FIXME: certificate not available")
            }
        }

}
#endif
