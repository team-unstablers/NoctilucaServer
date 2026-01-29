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
            return String(localized: "settings.security.alert.identity_not_exists.title", defaultValue: "사용 가능한 인증서 없음")
        case .internalPickerError:
            return String(localized: "settings.security.alert.internal_picker_error.title", defaultValue: "시스템 오류")
        }
    }

    var message: String {
        switch self {
        case .identityNotExists:
            return String(localized: "settings.security.alert.identity_not_exists.message", defaultValue: "Keychain에 사용 가능한 인증서가 없습니다.\nSSL 서버 용도의 인증서를 하나 이상 추가한 후 다시 시도해주세요.")
        case .internalPickerError:
            return String(localized: "settings.security.alert.internal_picker_error.message", defaultValue: "macOS 시스템에서 인증서 선택을 위한 UI를 제공하지 않았습니다.")
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
                Text(markdown: String(localized: "settings.security.auth_methods.title", defaultValue: "인증 수단"))
                Text(markdown: String(localized: "settings.security.auth_methods.description", defaultValue: "이 컴퓨터에 접속할 때 사용할 인증 수단을 설정합니다. 드래그-드롭으로 우선 순위를 변경할 수 있습니다. [더 알아보기…](http://google.com)"))
            }

            Section {
                IntegerField(value: $settings.quicTransport.listenPort) {
                    Text(markdown: String(localized: "settings.security.server_port.title", defaultValue: "서버 포트"))
                    Text(markdown: String(localized: "settings.security.server_port.description", defaultValue: "Noctiluca가 수신 대기할 포트를 설정합니다."))
                }
                if let identityInfo = identityInfo {
                    SettingsEntry(title: String(localized: "settings.security.server_certificate.title", defaultValue: "서버 인증서"), subtitle: String(localized: "settings.security.server_certificate.valid_until", defaultValue: "이 인증서는 \(identityInfo.notAfter.formatted(date: .numeric, time: .omitted))까지 유효합니다.")) {
                        VStack(alignment: .trailing) {
                            Text(identityInfo.commonName)
                            Button {
                                showCertificateDetailSheet = true
                            } label: {
                                Text(markdown: String(localized: "settings.security.server_certificate.view_details", defaultValue: "인증서 세부 정보 보기…"))
                            }
                            /*
                            Text(identityInfo.fingerprint.asFingerprintString())
                                .font(.subheadline.monospaced())
                             */
                        }
                    }
                    if passesSanityCheck == false {
                        SettingsEntry(title: String(localized: "settings.security.server_certificate.validation_failed.title", defaultValue: "⚠️ 유효성 검사 실패"), subtitle: String(localized: "settings.security.server_certificate.validation_failed.description", defaultValue: "인증서 유효성 검사에 실패했습니다. 클라이언트가 경고를 표시할 수 있습니다.")) {
                        }
                    }
                } else {
                    SettingsEntry(title: String(localized: "settings.security.server_certificate.not_set.title", defaultValue: "서버 인증서 지정되지 않음"), subtitle: String(localized: "settings.security.server_certificate.not_set.description", defaultValue: "서버 인증서가 지정되지 않았습니다. 서버 기동에 실패할 수 있습니다.")) {
                    }
                }
                Toggle(isOn: $settings.quicTransport.tlsUseAutoconf) {
                    Text(markdown: String(localized: "settings.security.tls_autoconf.title", defaultValue: "서버 인증서를 자동으로 구성하기"))
                    Text(markdown: String(localized: "settings.security.tls_autoconf.description", defaultValue: "자가 서명 인증서를 사용하여 QUIC 통신을 암호화합니다."))
                }
                
                if !settings.quicTransport.tlsUseAutoconf {
                    Toggle(isOn: $settings.quicTransport.tlsStrictValidation) {
                        Text(markdown: String(localized: "settings.security.tls_strict_validation.title", defaultValue: "엄격한 유효성 검사 사용하기"))
                        Text(markdown: String(localized: "settings.security.tls_strict_validation.description", defaultValue: "시스템의 트러스트 스토어를 기준으로 신뢰할 수 없는 인증서를 사용 시 경고를 표시합니다."))
                    }
                    SettingsEntry(title: String(localized: "settings.security.load_certificate.title", defaultValue: "인증서 불러오기")) {
                        /*
                        Button("파일 선택…") {

                        }
                         */
                        Button(String(localized: "settings.security.load_certificate.from_keychain", defaultValue: "Keychain에서 불러오기…")) {
                            showCertificatePicker()
                        }
                    }
                } else {
                     SettingsEntry(title: String(localized: "settings.security.self_signed_certificate.title", defaultValue: "자가 서명 인증서 설정")) {
                         Button(String(localized: "settings.security.self_signed_certificate.reissue", defaultValue: "인증서 재발급…")) {
                             do {
                                 try settings.quicTransport.autoconfigureIdentity()
                             } catch {
                                 // TODO: NSAlert
                             }
                         }
                    }
                   
                }

            } header: {
                Text(markdown: String(localized: "settings.security.transport_layer.title", defaultValue: "트랜스포트 레이어"))
                Text(markdown: String(localized: "settings.security.transport_layer.description", defaultValue: "Noctiluca에서는 QUIC 프로토콜을 사용하여 통신합니다. [더 알아보기…](http://google.com)"))
            }

            Section {
                Toggle(isOn: $settings.transport.disableServerVersionAnnouncement) {
                    Text(markdown: String(localized: "settings.security.protocol.hide_server_version.title", defaultValue: "서버 버전을 알리지 않기"))
                    Text(markdown: String(localized: "settings.security.protocol.hide_server_version.description", defaultValue: "서버 버전을 클라이언트에게 알리지 않습니다."))
                }

                Toggle(isOn: $settings.transport.disableSupportedFeaturesAnnouncement) {
                    Text(markdown: String(localized: "settings.security.protocol.hide_features.title", defaultValue: "사용 가능한 기능 목록을 알리지 않기"))
                    Text(markdown: String(localized: "settings.security.protocol.hide_features.description", defaultValue: "서버에서 지원하는 기능 목록을 클라이언트에게 알리지 않습니다. 호환성이 떨어질 수 있습니다."))
                }
                TextField(text: $settings.transport.motd, prompt: Text(markdown: String(localized: "settings.security.protocol.motd.placeholder", defaultValue: "[부자가 되는 가장 빠른 지름길은, 많은 돈을 버는 것입니다.]")).italic()) {
                    Text(markdown: String(localized: "settings.security.protocol.motd.title", defaultValue: "오늘의 메시지 (MOTD)"))
                    Text(markdown: String(localized: "settings.security.protocol.motd.description", defaultValue: "클라이언트가 접속할 때 표시할 오늘의 메시지를 설정합니다."))
                }
                TextField(text: $settings.transport.authChallengeMessage, prompt: Text(markdown: String(localized: "settings.security.protocol.auth_challenge_message.placeholder", defaultValue: "[Contoso Inc. - 관계자 외 접근을 금합니다.]")).italic()) {
                    Text(markdown: String(localized: "settings.security.protocol.auth_challenge_message.title", defaultValue: "인증 요청 시 표시할 메시지"))
                    Text(markdown: String(localized: "settings.security.protocol.auth_challenge_message.description", defaultValue: "클라이언트에게 인증 요청 시 표시할 메시지를 설정합니다."))
                }
            } header: {
                Text(markdown: String(localized: "settings.security.protocol.title", defaultValue: "프로토콜"))
                Text(markdown: String(localized: "settings.security.protocol.description", defaultValue: "Sirius 프로토콜의 동작 방식을 설정합니다. [더 알아보기…](http://google.com)"))
            }
        }
        .enumAlert(alertCase: $alertCase)
        .formStyle(.grouped)
        .sheet(isPresented: $showCertificateDetailSheet) {
            if let certificate = certificate {
                CertificateSheet(certificate: certificate)
            } else {
                Text(markdown: String(localized: "settings.security.server_certificate.load_failed", defaultValue: "인증서 정보를 불러올 수 없습니다."))
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
        
        panel.setAlternateButtonTitle(String(localized: "common.cancel", defaultValue: "취소"))
        panel.setInformativeText(   String(localized: "settings.security.certificate_picker.informative_text", defaultValue: "'서버 인증' (OID 1.3.6.1.5.5.7.3.1) 목적으로 발급된 인증서만 사용할 수 있습니다."))

        let response = panel.runModal(forIdentities: identities, message: String(localized: "settings.security.certificate_picker.message", defaultValue: "서버에서 사용할 인증서를 선택해 주세요."))
        
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
