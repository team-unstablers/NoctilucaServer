import SwiftUI

struct SecuritySessionSettingsTab: View {
    @Environment(\.sessionSettingsScope)
    private var scope: SessionSettingsScope

    @EnvironmentObject
    private var sessionSettingsStore: SessionSettingsStore

    private var tlsValidationPolicy: Binding<AppSettings.TLSValidationPolicy> {
        sessionSettingsStore.binding(for: scope, keyPath: \.security.tlsValidationPolicy)
    }

    private var disableClientVersionAnnouncement: Binding<Bool> {
        sessionSettingsStore.binding(for: scope, keyPath: \.security.disableClientVersionAnnouncement)
    }

    private var certificatePinningEnabled: Binding<Bool> {
        Binding(
            get: {
                sessionSettingsStore.settings(for: scope).security.pinning?.enabled ?? false
            },
            set: { newValue in
                sessionSettingsStore.updateSettings(for: scope) { settings in
                    var pinning = settings.security.pinning ?? SessionSettings.CertificatePinning()
                    pinning.enabled = newValue
                    settings.security.pinning = pinning
                }
            }
        )
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("자격 증명 관리 UI는 준비 중입니다.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("자격 증명")
            }

            Section {
                SettingsPicker(selection: tlsValidationPolicy) {
                    SettingsPickerItem(value: AppSettings.TLSValidationPolicy.unsafe) {
                        Text("수행하지 않기 **(위험!)**")
                        Text("서버의 SSL/TLS 인증서의 유효성 검사를 수행하지 않습니다.\n제 3자가 통신 내용을 훔쳐보거나 변조하는 중간자 공격 (MITM)에 취약하므로 권장하지 않습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: AppSettings.TLSValidationPolicy.default) {
                        Text("기본")
                        Text("모든 호스트가 신뢰받은 인증 기관으로부터 SSL/TLS 인증서를 발급받을 수 없다는 상황을 감안합니다.\n자가 서명 인증서를 사용한 호스트의 경우 경고 팝업을 표시합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: AppSettings.TLSValidationPolicy.strict) {
                        Text("엄격히")
                        Text("시스템의 트러스트 스토어를 기준으로 서버의 SSL/TLS 인증서를 엄격하게 검사합니다.\n자가 서명 인증서를 사용 중인 호스트의 경우 연결에 실패할 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("유효성 검사 정책")
                    Text("서버의 SSL/TLS 인증서의 유효성 검사 수준을 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if scope == .session {
                    Toggle(isOn: certificatePinningEnabled) {
                        Text("인증서 고정하기")
                        Text("서버의 SSL/TLS 인증서를 미리 지정한 인증서와 비교하여 일치하는 경우에만 연결을 허용합니다.")
                    }
                    
                    SettingsEntry(
                        title: "고정된 인증서 정보",
                        subtitle: "FIXME"
                    ) {
                    }
                }
               
            } header: {
                Text("트랜스포트 레이어")
                Text("Noctiluca에서는 QUIC 프로토콜을 사용하여 통신합니다.")
            }
            
            Section {
                Toggle(isOn: disableClientVersionAnnouncement) {
                    Text("클라이언트 버전을 알리지 않기")
                    Text("클라이언트 버전을 서버에게 알리지 않습니다.\n일부 서버에서는 접속을 거절하거나 기능을 제한할 수도 있습니다.")
                }
            } header: {
                Text("프로토콜")
                Text("Sirius 프로토콜의 동작 방식을 구성합니다.")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SecuritySessionSettingsTab()
        .environmentObject(SessionSettingsStore(loadFromDisk: false))
}
