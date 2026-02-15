import SwiftUI

struct InputSessionSettingsTab: View {
    @Binding
    var sessionSettings: SessionSettings

    let scope: SessionSettingsScope

    private func hackToggleBinding(_ hackId: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { sessionSettings.input.enabledKeyboardHacks.contains(hackId) },
            set: { enabled in
                if enabled {
                    sessionSettings.input.enabledKeyboardHacks.insert(hackId)
                } else {
                    sessionSettings.input.enabledKeyboardHacks.remove(hackId)
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                SettingsEntry(
                    title: String(localized: "session-settings.input.keyboard_hacks", defaultValue: "키보드 핵 (Hack) 설정"),
                    subtitle: String(localized: "session-settings.input.keyboard_hacks_desc", defaultValue: "사용자 편의를 위해 키보드 동작을 수정하거나 보완하도록 서버에 요청합니다.\n- 모든 서버가 이 Hack들을 지원하는 것은 아닙니다.\n- 일부 Hack은 상호 배타적입니다. 동시 사용 시 예기치 않은 동작이 발생할 수 있습니다.")
                ) {
                }
                
                /*
                Toggle(isOn: hackToggleBinding("app.noctiluca.hidio.hack.cjk.emulate_win32_ime_switch")) {
                    Text("Windows 스타일의 IME 전환")
                    Group {
                        Text("app.noctiluca.hidio.hack.cjk.emulate_win32_ime_switch")
                            .font(.caption2.monospaced())
                        Text("Windows 스타일의 IME 전환 동작을 에뮬레이트합니다.\nAlt + Shift를 누르면 다음 입력기로 전환합니다.")
                            .font(.subheadline)
                    }
                        .foregroundStyle(.secondary)
                }
                 */
                
                Toggle(isOn: hackToggleBinding("app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle")) {
                    Text(String(localized: "session-settings.input.hack.hangul_toggle", defaultValue: "한국어: Windows 스타일의 한/영 전환"))
                    Group {
                        Text("app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle")
                            .font(.caption2.monospaced())
                        Text(String(localized: "session-settings.input.hack.hangul_toggle_desc", defaultValue: "Windows 스타일의 한/영 전환 동작을 에뮬레이트합니다.\n오른쪽 ⌘ (Command)키와 ⌥ (Option) 키를 한/영 전환으로 사용합니다."))
                            .font(.subheadline)
                    }
                        .foregroundStyle(.secondary)
                }

                /*
                Toggle(isOn: hackToggleBinding("app.noctiluca.hidio.hack.cjk.emulate_win32_kana_toggle")) {
                    Text("일본어: Windows 스타일의 가나 / 로마자 전환")
                    Group {
                        Text("app.noctiluca.hidio.hack.cjk.emulate_win32_kana_toggle")
                            .font(.caption2.monospaced())
                        Text("비-JIS 배열 키보드에서 Windows 스타일의 가나 / 로마자 전환 동작을 에뮬레이트합니다.\n왼쪽 ⌥ (Option) + ` 키를 가나 / 로마자 전환으로 사용합니다.")
                            .font(.subheadline)
                    }
                        .foregroundStyle(.secondary)
                }
                 */
            } header: {
                Text(String(localized: "session-settings.input.experimental", defaultValue: "실험 기능"))
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    InputSessionSettingsTab(
        sessionSettings: .constant(SessionSettings(scope: .global)),
        scope: .global
    )
}
