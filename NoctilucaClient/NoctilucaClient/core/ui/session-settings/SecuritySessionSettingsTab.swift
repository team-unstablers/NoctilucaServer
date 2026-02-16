import SwiftUI

struct SecuritySessionSettingsTab: View {
    @Binding
    var sessionSettings: SessionSettings

    let scope: SessionSettingsScope
    let contactId: UUID?

    private var disableClientVersionAnnouncement: Binding<Bool> {
        Binding(
            get: { sessionSettings.security.disableClientVersionAnnouncement },
            set: { sessionSettings.security.disableClientVersionAnnouncement = $0 }
        )
    }

    private var certificatePinningEnabled: Binding<Bool> {
        Binding(
            get: {
                sessionSettings.security.pinning?.enabled ?? false
            },
            set: { newValue in
                var pinning = sessionSettings.security.pinning ?? SessionSettings.CertificatePinning()
                pinning.enabled = newValue
                sessionSettings.security.pinning = pinning
            }
        )
    }
    
    var body: some View {
        Form {
            Section {
                CredentialsListContainer(
                    sessionSettings: $sessionSettings,
                    scope: scope,
                    contactId: contactId
                )
            } header: {
                Text(markdown: String(localized: "session-settings.security.credentials", defaultValue: "자격 증명"))
            }

            Section {
                Toggle(isOn: disableClientVersionAnnouncement) {
                    Text(markdown: String(localized: "session-settings.security.protocol.disable_version", defaultValue: "클라이언트 버전을 알리지 않기"))
                    Text(markdown: String(localized: "session-settings.security.protocol.disable_version_desc", defaultValue: "클라이언트 버전을 서버에게 알리지 않습니다.\n일부 서버에서는 접속을 거절하거나 기능을 제한할 수도 있습니다."))
                }
            } header: {
                Text(markdown: String(localized: "session-settings.security.protocol", defaultValue: "프로토콜"))
                Text(markdown: String(localized: "session-settings.security.protocol_desc", defaultValue: "Sirius 프로토콜의 동작 방식을 구성합니다."))
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SecuritySessionSettingsTab(
        sessionSettings: .constant(SessionSettings(scope: .global)),
        scope: .global,
        contactId: nil
    )
}
