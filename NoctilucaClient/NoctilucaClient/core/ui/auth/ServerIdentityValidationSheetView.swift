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

enum ServerIdentityValidationSheetViewExtraInfo: Sendable {
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
    
    let leaf: SecCertificateLike
    let chain: [SecCertificateLike]
    
    let extraInfo: ServerIdentityValidationSheetViewExtraInfo
    let handler: (ServerIdentityValidationAction) -> Void

    @State
    var isCertificateDetailsExpanded: Bool = true


    enum Tab {
        case summary
        case certificateInfo
        case help
    }
    
    @State
    private var selectedTab: Tab = .summary
    
    var tintColor: Color {
        switch extraInfo {
        case .fingerprintMismatch(_, _):
            return .red
        default:
            return .accentColor
        }
    }
    
    @ViewBuilder
    var summaryTab: some View {
        VStack(alignment: .leading) {
            switch extraInfo {
            case .fingerprintMismatch(let expectedFingerprint, let actualFingerprint):
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "auth.identity.danger", defaultValue: "위험"))
                        .font(.title)
                        .foregroundStyle(.red)
                    Text(String(localized: "auth.identity.fingerprint_mismatch.title", defaultValue: "서버 인증서 지문이 일치하지 않습니다!"))
                        .font(.title2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bold()
                .padding(.bottom, 6)
                .foregroundStyle(.primary)

                Text(String(format: String(localized: "auth.identity.fingerprint_mismatch_format", defaultValue: "`%@`에서 인증서를 제시했지만, 인증서 지문이 저번에 접속했을 때와 다릅니다."), hostname))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.bottom, 12)
                
                VStack(alignment: .center, spacing: 16) {
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text(String(localized: "auth.identity.expected_fingerprint", defaultValue: "이 클라이언트가 기억하고 있는 인증서 지문"))
                            .font(.system(size: 14))
                            .bold()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(expectedFingerprint.byCharWrapping)
                        }
                        .padding()
                        .border(.tertiary)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(String(localized: "auth.identity.actual_fingerprint", defaultValue: "서버에서 제시한 인증서 지문"))
                            .font(.system(size: 14))
                            .bold()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(actualFingerprint.byCharWrapping)
                        }
                        .padding()
                        .border(.tertiary)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            case .none:
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "auth.identity.warning", defaultValue: "경고"))
                        .font(.title)
                        .foregroundStyle(.yellow)
                    Text(String(localized: "auth.identity.untrusted.title", defaultValue: "서버의 인증서를 검증할 수 없습니다."))
                        .font(.title2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bold()
                .padding(.bottom, 6)
                .foregroundStyle(.primary)

                Text(String(format: String(localized: "auth.identity.untrusted_format", defaultValue: "`%@`에서 인증서를 제시했지만, 시스템의 트러스트 스토어에서 이를 신뢰할 수 없다고 판단했습니다."), hostname))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.bottom, 12)
                
                Spacer()
            }
        }
        .padding()
    }
    
    @ViewBuilder
    var certificateInfoTab: some View {
        VStack {
            NOCCertificateView(leaf: leaf, chain: chain)
                .padding()
        }
    }
    
    @ViewBuilder
    var helpTab: some View {
        ScrollView {
            VStack {
                switch extraInfo {
                case .fingerprintMismatch(_, _):
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "auth.identity.help.simple_explanation.mismatch.body_1", defaultValue: "다른 컴퓨터가 **신분을 위조**해서 사기를 치려고 하는 것 같습니다."))
                            Text(String(localized: "auth.identity.help.simple_explanation.mismatch.body_2", defaultValue: "Noctiluca Navigator는 접속하는 모든 컴퓨터의 신분증 (인증서)의 복사본을 받아둡니다. 이번에 받은 신분증은 저번에 받은 것과 일치하지 않았기 때문에 경고를 표시합니다."))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                    } label: {
                        Text(String(localized: "auth.identity.help.what_happened.title", defaultValue: "무슨 의미인지 하나도 모르겠어요. 최대한 쉽게 설명해 주세요."))
                            .multilineTextAlignment(.leading)
                            .disclosureLabelStyle()
                    }
                    .padding(.bottom, 12)
                    
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "auth.identity.help.why_warning.mismatch.body_1", defaultValue: "이 경고는 다음과 같은 상황에서 발생할 수 있습니다:"))
                            Text(String(localized: "auth.identity.help.why_warning.mismatch.body_2", defaultValue: "• 서버 관리자가 인증서를 교체하였습니다."))
                            Text(String(localized: "auth.identity.help.why_warning.mismatch.body_3", defaultValue: "• **중간자 공격**(MITM)의 가능성이 있습니다: 누군가가 악의적인 목적으로 통신 내용을 훔쳐보거나 변조하려 할 수도 있습니다."))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                    } label: {
                        Text(String(localized: "auth.identity.help.why_warning.title", defaultValue: "이 경고는 왜 표시되나요?"))
                            .disclosureLabelStyle()
                    }
                    .padding(.bottom, 12)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "auth.identity.help.consequences.mismatch.body_1", defaultValue: "최악의 경우, 비밀번호나 기밀 정보가 유출될 수 있습니다."))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                    } label: {
                        Text(String(localized: "auth.identity.help.consequences.title", defaultValue: "만약 계속 진행하면 어떻게 되나요?"))
                            .multilineTextAlignment(.leading)
                            .disclosureLabelStyle()
                    }
                    .padding(.bottom, 12)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "auth.identity.help.what_to_do.mismatch.body_1", defaultValue: "• 안전하지 않은 인터넷 환경 (공개된 Wi-Fi 등)에서 작업하고 있다면, 접속을 해제하고 안전이 보장되는 환경에서 다시 시도하십시오."))
                            Text(String(localized: "auth.identity.help.what_to_do.mismatch.body_2", defaultValue: "• 만약 최근에 인증서를 직접 교체한 기억이 있으시다면 계속 진행하셔도 괜찮습니다."))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                    } label: {
                        Text(String(localized: "auth.identity.help.what_to_do.title", defaultValue: "그럼 저는 어떻게 해야 하나요?"))
                            .multilineTextAlignment(.leading)
                            .disclosureLabelStyle()
                    }
                    .padding(.bottom, 12)
                default:
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "auth.identity.help.simple_explanation.untrusted.body_1", defaultValue: "컴퓨터가 제시한 신분증 (인증서)의 진위를 검증할 수 없기 때문에 이 경고가 표시되었습니다.\n"))
                            Text(String(localized: "auth.identity.help.simple_explanation.untrusted.body_2", defaultValue: "컴퓨터끼리 암호화된 통신을 할 때는, 신분증 (인증서)이 필요합니다. 인증서를 발급 받는 방법은 크게 2가지가 있습니다.\n"))
                            Text(String(localized: "auth.identity.help.simple_explanation.untrusted.body_3", defaultValue: "• **신뢰받는 인증 기관에서 발급받기**: 지금 보고 계신 것과 같은 경고가 표시되지 않게 되지만, 비용을 지불해야 합니다."))
                            Text(String(localized: "auth.identity.help.simple_explanation.untrusted.body_4", defaultValue: "• **자가 서명 인증서 발급하기**: 자기 자신의 인증서를 직접 만드는 방법입니다. 다른 컴퓨터들이 진위를 검증할 수 없기 때문에 이러한 오류가 표시됩니다.\n"))
                            Text(String(localized: "auth.identity.help.simple_explanation.untrusted.body_5", defaultValue: "이번에 접속을 시도한 컴퓨터는 진위를 알 수 없는 신분증을 제시하였습니다."))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                    } label: {
                        Text(String(localized: "auth.identity.help.what_happened.title", defaultValue: "무슨 의미인지 하나도 모르겠어요. 최대한 쉽게 설명해 주세요."))
                            .multilineTextAlignment(.leading)
                            .disclosureLabelStyle()
                    }
                    .padding(.bottom, 12)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "auth.identity.help.why_warning.untrusted.body_1", defaultValue: "이 경고는 다음과 같은 상황에서 표시될 수 있습니다:"))
                            Text(String(localized: "auth.identity.help.why_warning.untrusted.body_2", defaultValue: "• 자가 서명 인증서를 사용한 경우"))
                            Text(String(localized: "auth.identity.help.why_warning.untrusted.body_3", defaultValue: "• 시스템의 트러스트 스토어가 낡은 상태인 경우"))
                            Text(String(localized: "auth.identity.help.why_warning.untrusted.body_4", defaultValue: "• 시스템의 시계가 틀어져 실제 시각과 커다란 차이가 나는 경우"))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                    } label: {
                        Text(String(localized: "auth.identity.help.why_warning.title", defaultValue: "이 경고는 왜 표시되나요?"))
                            .disclosureLabelStyle()
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding()
        }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                self.summaryTab
                    .tabItem {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(String(localized: "auth.identity.tab.warning", defaultValue: "경고"))
                    }
                    .tag(Tab.summary)
                    .id(Tab.summary)

                self.certificateInfoTab
                    .tabItem {
                        Image(systemName: "info.square.fill")
                        Text(String(localized: "auth.identity.tab.certificate_info", defaultValue: "인증서 정보"))
                    }
                    .tag(Tab.certificateInfo)
                    .id(Tab.certificateInfo)

                self.helpTab
                    .tabItem {
                        Image(systemName: "questionmark.circle.fill")
                        Text(String(localized: "auth.identity.tab.help", defaultValue: "도움말"))
                    }
                    .tag(Tab.help)
                    .id(Tab.help)

            }
            
            .tabViewStyle(.tabBarOnly)
            .navigationTitle(String(localized: "auth.identity.navigation_title", defaultValue: "인증서 검증 실패"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#else
            .frame(minHeight: 480)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        handler(.disconnect)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(.primary)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(String(localized: "auth.identity.trust_once", defaultValue: "이번만 신뢰하기")) {
                            handler(.proceed(.once))
                        }
                        Button(String(localized: "auth.identity.trust_always", defaultValue: "항상 신뢰하기")) {
                            handler(.proceed(.always))
                        }
                    } label: {
                        Text(String(localized: "auth.identity.proceed", defaultValue: "계속 진행"))
                    }
                }
#else
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .cancel) {
                        handler(.disconnect)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(String(localized: "auth.identity.trust_once", defaultValue: "이번만 신뢰하기")) {
                            handler(.proceed(.once))
                        }
                        Button(String(localized: "auth.identity.trust_always", defaultValue: "항상 신뢰하기")) {
                            handler(.proceed(.always))
                        }
                    } label: {
                        Text(String(localized: "auth.identity.proceed", defaultValue: "계속 진행"))
                    }
                }
#endif
            }
            .tint(tintColor)
        }
        .interactiveDismissDisabled(true)
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
    var issuer: String?
    var algorithmDescription: String?
    var publicKey: Data?
}
#endif

/// 키체인에서 아무 인증서나 적당히 고릅니다
fileprivate func pickCertificate(_ label: String) -> SecCertificateLike? {
#if os(macOS)
    let result = SRKeychain.shared.queryItem(by: label, clazz: .certificate)
    guard let item = try? result.get() else {
        return nil
    }

    return item as! SecCertificate
#else
    return MockedCertificate(
        commonName: label,
        notBefore: Date(),
        notAfter: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
        fingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B",
        issuer: "Contoso Inc.",
        algorithmDescription: "RSA 2048-bit",
        publicKey: try? SRSecurity.shared.createSecureRandomBytes(count: 256),
    )
#endif
}

#Preview {
    let leaf = pickCertificate("전자 병아리 #3156")!
    let chain = [
        pickCertificate("전자 병아리 주식회사 Intermediate CA")!,
        pickCertificate("전자 병아리 주식회사 Root CA")!
    ]
    
    #if os(iOS)
    VStack {}
        .sheet(isPresented: .constant(true)) {
            ServerIdentityValidationSheetView(
                hostname: "resource01.internal.contoso.com",
                leaf: leaf,
                chain: chain,
                // extraInfo: .fingerprintMismatch(expectedFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B", actualFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B")
                extraInfo: .none,
            ) { action in
                print(action)
            }
        }
    #else
        ServerIdentityValidationSheetView(
                hostname: "resource01.internal.contoso.com",
                leaf: leaf,
                chain: chain,
                // extraInfo: .fingerprintMismatch(expectedFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B", actualFingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B")
                extraInfo: .none,
            ) { action in
                print(action)
            }
    #endif

        


}
#endif
