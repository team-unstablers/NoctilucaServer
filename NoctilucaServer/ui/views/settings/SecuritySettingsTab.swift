import SwiftUI

import Cocoa
import Security
import SecurityInterface

import SiriusKit

fileprivate enum SecuritySettingsTabAlertCase: AlertCase {
    /// showCertificatePicker(): 키체인에 서버용 인증서가 없습니다
    case identityNotExists
    case internalPickerError
    
    var id: String {
        switch self {
        case .identityNotExists:
            return "identityNotExists"
        case .internalPickerError:
            return "internalPickerError"
        }
    }
    
    var title: String {
        switch self {
        case .identityNotExists:
            return "사용 가능한 인증서 없음"
        case .internalPickerError:
            return "시스템 오류"
        }
    }
    
    var message: String {
        switch self {
        case .identityNotExists:
            return "Keychain에 사용 가능한 인증서가 없습니다.\nSSL 서버 용도의 인증서를 하나 이상 추가한 후 다시 시도해주세요."
        case .internalPickerError:
            return "macOS 시스템에서 인증서 선택을 위한 UI를 제공하지 않았습니다."
        }
    }
}

struct SecuritySettingsTab: View {
    @Binding
    var settings: AppSettings
    
    @State
    var identityInfo: QUICServerIdentityInfo? = nil
    
    @State
    var certificate: SecCertificate? = nil
    
    @State
    var passesSanityCheck: Bool? = nil

    @State
    var showCertificateDetailSheet: Bool = false
    
    @State
    fileprivate var alertCase: SecuritySettingsTabAlertCase? = nil

    var body: some View {
        Form {
            Section {
                AuthMethodContainer(authMethods: $settings.security.allowedEntries)
            } header: {
                Text("인증 수단")
                Text("이 컴퓨터에 접속할 때 사용할 인증 수단을 설정합니다. 드래그-드롭으로 우선 순위를 변경할 수 있습니다. [더 알아보기…](http://google.com)")
            }

            Section {
                IntegerField(value: $settings.quicTransport.listenPort) {
                    Text("서버 포트")
                    Text("Noctiluca가 수신 대기할 포트를 설정합니다.")
                }
                if let identityInfo = identityInfo {
                    SettingsEntry(title: "서버 인증서", subtitle: "이 인증서는 \(identityInfo.notAfter.formatted(date: .numeric, time: .omitted))까지 유효합니다.") {
                        VStack(alignment: .trailing) {
                            Text(identityInfo.commonName)
                            Button {
                                showCertificateDetailSheet = true
                            } label: {
                                Text("인증서 세부 정보 보기…")
                            }
                            /*
                            Text(identityInfo.fingerprint.asFingerprintString())
                                .font(.subheadline.monospaced())
                             */
                        }
                    }
                    if passesSanityCheck == false {
                        SettingsEntry(title: "⚠️ 유효성 검사 실패", subtitle: "인증서 유효성 검사에 실패했습니다. 클라이언트가 경고를 표시할 수 있습니다.") {
                        }
                    }
                } else {
                    SettingsEntry(title: "서버 인증서 지정되지 않음", subtitle: "서버 인증서가 지정되지 않았습니다. 서버 기동에 실패할 수 있습니다.") {
                    }
                }
                Toggle(isOn: $settings.quicTransport.tlsUseAutoconf) {
                    Text("서버 인증서를 자동으로 구성하기")
                    Text("자가 서명 인증서를 사용하여 QUIC 통신을 암호화합니다.")
                }
                
                if !settings.quicTransport.tlsUseAutoconf {
                    Toggle(isOn: $settings.quicTransport.tlsStrictValidation) {
                        Text("엄격한 유효성 검사 사용하기")
                        Text("시스템의 트러스트 스토어를 기준으로 신뢰할 수 없는 인증서를 사용 시 경고를 표시합니다.")
                    }
                    SettingsEntry(title: "인증서 불러오기") {
                        /*
                        Button("파일 선택…") {
                            
                        }
                         */
                        Button("Keychain에서 불러오기…") {
                            showCertificatePicker()
                        }
                    }
                } else {
                     SettingsEntry(title: "자가 서명 인증서 설정") {
                         Button("인증서 재발급…") {
                             do {
                                 try settings.quicTransport.autoconfigureIdentity()
                             } catch {
                                 // TODO: NSAlert
                             }
                         }
                    }
                   
                }

            } header: {
                Text("트랜스포트 레이어")
                Text("Noctiluca에서는 QUIC 프로토콜을 사용하여 통신합니다. [더 알아보기…](http://google.com)")
            }

            Section {
                Toggle(isOn: $settings.transport.disableServerVersionAnnouncement) {
                    Text("서버 버전을 알리지 않기")
                    Text("서버 버전을 클라이언트에게 알리지 않습니다.")
                }

                Toggle(isOn: $settings.transport.disableSupportedFeaturesAnnouncement) {
                    Text("사용 가능한 기능 목록을 알리지 않기")
                    Text("서버에서 지원하는 기능 목록을 클라이언트에게 알리지 않습니다. 호환성이 떨어질 수 있습니다.")
                }
                TextField(text: $settings.transport.motd, prompt: Text("[부자가 되는 가장 빠른 지름길은, 많은 돈을 버는 것입니다.]").italic()) {
                    Text("오늘의 메시지 (MOTD)")
                    Text("클라이언트가 접속할 때 표시할 오늘의 메시지를 설정합니다.")
                }
                TextField(text: $settings.transport.authChallengeMessage, prompt: Text("[Contoso Inc. - 관계자 외 접근을 금합니다.]").italic()) {
                    Text("인증 요청 시 표시할 메시지")
                    Text("클라이언트에게 인증 요청 시 표시할 메시지를 설정합니다.")
                }
            } header: {
                Text("프로토콜")
                Text("Sirius 프로토콜의 동작 방식을 설정합니다. [더 알아보기…](http://google.com)")
            }
        }
        .enumAlert(alertCase: $alertCase)
        .formStyle(.grouped)
        .sheet(isPresented: $showCertificateDetailSheet) {
            if let certificate = certificate {
                CertificateSheet(certificate: certificate)
            } else {
                Text("인증서 정보를 불러올 수 없습니다.")
            }
        }
        .onChange(of: settings.quicTransport.identity) { _, _ in
            self.updateIdentityInfo()
        }
        .onChange(of: settings.quicTransport.tlsStrictValidation) { _, _ in
            self.updateIdentityInfo()
        }
        .onAppear {
            self.updateIdentityInfo()
        }
    }
    
    func updateIdentityInfo() {
        self.identityInfo = nil
        self.certificate = nil
        self.passesSanityCheck = nil
        
        Task {
            guard let identity = settings.quicTransport.identity else {
                self.identityInfo = nil
                self.certificate = nil
                self.passesSanityCheck = nil
                return
            }
            
            self.identityInfo = try? await identity.identityInfo()
            self.certificate = try? await identity.secCertificate()
            self.passesSanityCheck = (try? await identity.sanityCheck(strict: self.settings.quicTransport.tlsStrictValidation)) ?? false
        }
    }
    
    func showCertificatePicker() {
        // SSL 서버 용도의 인증서로만 제한한다
        let sslServerPolicy = SecPolicyCreateSSL(true, nil)

        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecMatchPolicy as String: sslServerPolicy,
        ]
        
        var itemResult: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &itemResult)
        
        guard status == errSecSuccess,
              let identities = itemResult as? [SecIdentity] else {
            self.alertCase = .identityNotExists
            return
        }
        
        // 2. SFChooseIdentityPanel 띄우기
        guard let panel = SFChooseIdentityPanel.shared() else {
            self.alertCase = .internalPickerError
            return
        }
        
        panel.setAlternateButtonTitle("취소")
        panel.setInformativeText("'서버 인증' (OID 1.3.6.1.5.5.7.3.1) 목적으로 발급된 인증서만 사용할 수 있습니다.")
        
        let response = panel.runModal(forIdentities: identities, message: "서버에서 사용할 인증서를 선택해 주세요.")
        
        if response == NSApplication.ModalResponse.OK.rawValue {
            if let identity = panel.identity() {
                guard let keychainLabel = identity.takeUnretainedValue().extractLabel()
                else {
                    return
                }
                
                self.settings.quicTransport.identity = .keychain(identifier: keychainLabel)
            }
        }
    }
}

fileprivate extension Data {
    func asFingerprintString() -> String {
        return self.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
