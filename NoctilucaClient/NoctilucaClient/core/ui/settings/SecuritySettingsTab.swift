import SwiftUI

struct SecuritySettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsPicker(selection: $settingsStore.settings.security.tlsValidationPolicy) {
                    SettingsPickerItem(value: AppSettings.TLSValidationPolicy.unsafe) {
                        Text(String(localized: "settings.security.tls_validation.unsafe.title", defaultValue: "수행하지 않기 **(위험!)**"))
                        Text(String(localized: "settings.security.tls_validation.unsafe.description", defaultValue: "서버의 SSL/TLS 인증서의 유효성 검사를 수행하지 않습니다.\n제 3자가 통신 내용을 훔쳐보거나 변조하는 중간자 공격 (MITM)에 취약하므로 권장하지 않습니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: AppSettings.TLSValidationPolicy.default) {
                        Text(String(localized: "settings.security.tls_validation.default.title", defaultValue: "기본"))
                        Text(String(localized: "settings.security.tls_validation.default.description", defaultValue: "모든 호스트가 신뢰받은 인증 기관으로부터 SSL/TLS 인증서를 발급받을 수 없다는 상황을 감안합니다.\n자가 서명 인증서를 사용한 호스트의 경우 경고 팝업을 표시합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: AppSettings.TLSValidationPolicy.strict) {
                        Text(String(localized: "settings.security.tls_validation.strict.title", defaultValue: "엄격히"))
                        Text(String(localized: "settings.security.tls_validation.strict.description", defaultValue: "시스템의 트러스트 스토어를 기준으로 서버의 SSL/TLS 인증서를 엄격하게 검사합니다.\n자가 서명 인증서를 사용 중인 호스트의 경우 연결에 실패할 수 있습니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(String(localized: "settings.security.tls_validation.title", defaultValue: "유효성 검사 정책"))
                    Text(String(localized: "settings.security.tls_validation.description", defaultValue: "서버의 SSL/TLS 인증서의 유효성 검사 수준을 설정합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "settings.security.transport.header", defaultValue: "트랜스포트 레이어"))
                Text(String(localized: "settings.security.transport.header.description", defaultValue: "Noctiluca에서는 QUIC 프로토콜을 사용하여 통신합니다."))
            }
            
            Section {
                Toggle(isOn: $settingsStore.settings.security.disableClientVersionAnnouncement) {
                    Text(String(localized: "settings.security.protocol.disable_version_announcement.title", defaultValue: "클라이언트 버전을 알리지 않기"))
                    Text(String(localized: "settings.security.protocol.disable_version_announcement.description", defaultValue: "클라이언트 버전을 서버에게 알리지 않습니다.\n일부 서버에서는 접속을 거절하거나 기능을 제한할 수도 있습니다."))
                }
            } header: {
                Text(String(localized: "settings.security.protocol.header", defaultValue: "프로토콜"))
                Text(String(localized: "settings.security.protocol.header.description", defaultValue: "Sirius 프로토콜의 동작 방식을 구성합니다."))
            }
        }
        .formStyle(.grouped)
    }
}
