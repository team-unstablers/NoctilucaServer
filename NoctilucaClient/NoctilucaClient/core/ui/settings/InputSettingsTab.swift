import SwiftUI
import SiriusKitClient

struct InputSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore
    
#if os(macOS)
    @State
    private var isMonitoringTCCGranted: Bool = TCCUtil.shared.isAccessGranted(for: .inputMonitoring)
#endif
    
    var body: some View {
        Form {
#if os(macOS)
            Section {
                Toggle(isOn: $settingsStore.settings.input.enableExclusiveMode) {
                    Text("독점 모드 활성화")
                    Text("키보드와 마우스를 잠그는 독점 모드를 활성화합니다.\n- ⌘Q를 포함한 모든 키보드 단축키를 그대로 사용할 수 있게 됩니다.\n- 마우스 입력이 상대 좌표로 전달됩니다. 3D 툴이나 FPS 게임 등에서 유용하게 동작합니다.")
                }
                .disabled(!isMonitoringTCCGranted)
                
                if !isMonitoringTCCGranted {
                    SettingsEntry(
                        title: "독점 모드 사용할 수 없음",
                        subtitle: "입력 모니터링 권한이 주어지지 않아 독점 모드를 사용할 수 없습니다.\n설정을 변경한 후에는 Noctiluca Navigator를 다시 시작해야 합니다."
                    ) {
                        HStack(spacing: 8) {
                            Button("설정 열기") {
                                TCCUtil.shared.openSystemPreferences(for: .inputMonitoring)
                            }
                        }
                    }
                }
                
                if settingsStore.settings.input.enableExclusiveMode {
                    SettingsEntry(title: "독점 모드 해제 단축키", subtitle: "키보드 / 마우스가 잠긴 상태에서 독점 모드를 해제하는 단축키를 설정합니다.") {
                        HStack {
                            KeySequenceLabel(keySequence: settingsStore.settings.input.unlockKeySequence)
                            KeySequenceCapturer(
                                keySequence: $settingsStore.settings.input.unlockKeySequence,
                                policy: .none,
                                default: KeySequence(modifier: [.KEY_LEFTALT], key: .KEY_ESC)
                            ) {
                                Text("변경")
                            }
                        }
                    }
                }
            } header: {
                Text("입력 설정")
                Text("전반적인 입력 설정을 구성합니다.")
            }
#endif
            
            Section {
                KeyboardModifierOverrideSection(input: $settingsStore.settings.input)
            } header: {
                Text("키보드 입력 설정")
                Text("키보드 입력과 관련된 설정을 구성합니다.")
            }

            
            /*
            Section {
                SettingsEntry(title: "키매핑 테이블 (고급 기능)", subtitle: "키매핑 테이블을 직접 편집합니다.\n잘못 편집할 경우 입력 기능이 정상적으로 동작하지 않을 수 있습니다.") {
                    Button("기본값으로 복원") {}
                    Button("설정…") {}
                }
            }
             */
            
            Section {
                MouseRedirectionMethodPicker(input: $settingsStore.settings.input)
#if os(iOS)
                if DeviceKind.current == .iPad {
                    Toggle(isOn: $settingsStore.settings.input.enableGCMouse) {
                        Text("GCMouse를 보조 수단으로 사용하기")
                        Text("Apple의 [GameController.framework](https://developer.apple.com/documentation/gamecontroller) 에서 제공하는 GCMouse를 보조 입력 수단으로 사용합니다.\n이 앱을 전체 화면으로 사용 중인 상태에서 블루투스 마우스를 연결했을 때, 휠 스크롤, 추가 버튼에 대한 지원을 받을 수 있게 됩니다.")
                    }
                }
#endif
            } header: {
                Text("마우스 입력 설정")
                Text("마우스 입력과 관련된 설정을 구성합니다.")
            } footer: {
#if os(iOS)
                switch settingsStore.settings.input.touchInputMode {
                case .touch:
                    Text("참고:\n- 터치 모드는 탭 시 해당 위치로 이동 후 클릭합니다.\n- 드래그는 한 손가락으로 바로 클릭+드래그로 처리됩니다.")
                case .trackpad:
                    Text("참고:\n- 트랙패드 모드는 상대 좌표로 커서를 이동합니다.\n- 드래그는 긴 누름 또는 두 손가락 조합으로 실행됩니다.")
                }
#endif
            }
            
            Section {
                Toggle(isOn: $settingsStore.settings.input.invertMouseButtons) {
                    Text("마우스 좌우 버튼을 반전하기")
                    Text("2-버튼 마우스의 좌우 버튼 위치를 반전하여 사용합니다.\n왼손을 주로 사용하는 사용자에게 도움이 될 수 있습니다.")
                }
                Toggle(isOn: $settingsStore.settings.input.invertVerticalScroll) {
                    Text("세로↕ 스크롤 방향을 반전하기")
                    Text("세로 스크롤 시 상하 방향을 반전시킵니다.")
                }
                Toggle(isOn: $settingsStore.settings.input.invertHorizontalScroll) {
                    Text("가로↔ 스크롤 방향을 반전하기")
                    Text("가로 스크롤 시 좌우 방향을 반전시킵니다.")
                }
            }
            
            Section {
#if os(iOS)
                SettingsEntry(title: "트랙패드 이동 배수", subtitle: "트랙패드 모드에서 커서 이동량에 배수를 적용합니다.\n값이 클수록 커서가 더 멀리 이동합니다.") {
                    Slider(value: $settingsStore.settings.input.trackpadMoveMultiplier, in: 0.5...2.0, step: 0.1) {
                    } minimumValueLabel: {
                        Text("0.5x")
                    } maximumValueLabel: {
                        Text("2.0x")
                    }
                }
#endif
                SettingsEntry(title: "마우스 스크롤 배수", subtitle: "마우스 스크롤에 배수 값을 적용하여 전송합니다.\n값이 클수록 스크롤 속도가 빨라집니다.") {
                    Slider(value: $settingsStore.settings.input.mouseScrollMultiplier, in: 0.5...1.5, step: 0.25) {
                        
                    } minimumValueLabel: {
                        Text("0.5x")
                    } maximumValueLabel: {
                        Text("1.5x")
                    }
                }
            } header: {
                Text("고급 설정")
                Text("입력 관련 고급 설정을 구성합니다.")
            }
            
            Section {
                SettingsEntry(title: "도와주세요, 잘못 건드렸더니 망가졌어요", subtitle: "이 버튼을 누르면 입력 관련 설정이 초기화됩니다.") {
                    Button("입력 관련 설정 초기화") {
                        settingsStore.resetInputSettings()
                    }
                }
            } header: {
                Text("문제 해결")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    InputSettingsTab()
        .environmentObject(SettingsStore.shared)
        .frame(minHeight: 720)
}
