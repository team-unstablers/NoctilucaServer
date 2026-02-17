import SwiftUI

struct SecuritySessionSettingsTab: View {
#if false
    static let KEYSTROKES: [KeyEquivalent] = [
        .upArrow,
        .upArrow,
        .downArrow,
        .downArrow,
        .leftArrow,
        .rightArrow,
        .leftArrow,
        .rightArrow,
        .init("b"),
        .init("a")
    ]
    
    @State
    var shouldPresentAdditionalSettings: Bool = false
    
    @State
    var additionalSettingsGuardIndex = 0
#endif

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
            
#if false
            if shouldPresentAdditionalSettings {
                /// 인터넷을 자유롭게 사용하지 못하는 사람들에게 도움이 되었으면 좋겠습니다
                Section {
                    Toggle(isOn: .constant(false)) {
                        Text(markdown: String(localized: "session-settings.security.protocol.urara.h3", defaultValue: "ALPN 어나운스 시 'h3'을 대신 사용하기"))
                        Text(markdown: String(localized: "session-settings.security.protocol.urara.h3.desc", defaultValue: "일부 네트워크 환경에서의 호환성을 개선시킬 수 있을거라 믿고 싶습니다."))
                    }
                } header: {
                    Text(markdown: String(localized: "session-settings.security.protocol.urara.title", defaultValue: "개발용 설정: 麗 (우라라) 모드"))
                    Text(markdown: String(localized: "session-settings.security.protocol.urara.desc", defaultValue: "君の 夢は うららかに"))
                }
            }
#endif
        }
        .formStyle(.grouped)
#if false
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .init("b"), .init("a")]) {
            guard !shouldPresentAdditionalSettings else { return .ignored }
            
            if $0.key == Self.KEYSTROKES[additionalSettingsGuardIndex] {
                additionalSettingsGuardIndex += 1
                if additionalSettingsGuardIndex >= Self.KEYSTROKES.count {
                    shouldPresentAdditionalSettings = true
                    additionalSettingsGuardIndex = 0
                }
            } else {
                additionalSettingsGuardIndex = 0
            }
            
            return .handled
        }
#endif
    }
}

#Preview {
    SecuritySessionSettingsTab(
        sessionSettings: .constant(SessionSettings(scope: .global)),
        scope: .global,
        contactId: nil
    )
}
