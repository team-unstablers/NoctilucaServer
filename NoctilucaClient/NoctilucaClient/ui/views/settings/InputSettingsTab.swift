import SwiftUI
import SiriusKitClient

struct InputSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore
    
    var body: some View {
        Form {
            Section {
                SettingsEntry(title: "입력 잠금 해제 단축키", subtitle: "키보드 / 마우스가 잠긴 상태에서 입력 잠금을 해제하는 단축키를 설정합니다.") {
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
            } header: {
                Text("입력 설정")
                Text("전반적인 입력 설정을 구성합니다.")
            }
            
            Section {
                KeyboardRedirectionMethodPicker(input: $settingsStore.settings.input)
            } header: {
                Text("키보드 입력 설정")
                Text("키보드 입력과 관련된 설정을 구성합니다.")
            }

#if os(macOS)
            if settingsStore.settings.input.redirectionMethod == .cocoaEventTap {
                Section {
                    let isInputMonitoringGranted = TCCUtil.shared.isAccessGranted(for: .inputMonitoring)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isInputMonitoringGranted ? "Input Monitoring 권한이 허용되었습니다." : "Input Monitoring 권한이 필요합니다.")
                            .font(.headline)
                        Text("권한이 없으면 Cocoa Event Tap을 사용할 수 없어 GameController 방식으로 자동 폴백됩니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("설정 열기") {
                            TCCUtil.shared.openSystemPreferences(for: .inputMonitoring)
                        }
                        Button("다시 시도") {
                            TCCUtil.shared.requestAccess(for: .inputMonitoring)
                        }
                    }
                } header: {
                    Text("입력 권한 상태")
                }
            }
#endif
            
            Section {
                KeyboardModifierOverrideSection(input: $settingsStore.settings.input)
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
            } header: {
                Text("마우스 입력 설정")
                Text("마우스 입력과 관련된 설정을 구성합니다.")
            } footer: {
                if settingsStore.settings.input.mouseMoveMode == .relative {
#if os(macOS)
                        // TODO: 마우스 / 키보드 캡쳐 해제 단축키 추가해야 함
                    Text("참고:\n- 이 방식은 마우스를 잠급니다. 미리 설정된 단축키를 누르면 마우스 잠금이 해제됩니다.")
#else
                    Text("참고:\n- 이 방식은 마우스를 잠급니다. ⎋ (escape) 키를 누르면 마우스 잠금이 해제됩니다.\n- iPad에서는 멀티 태스킹이 활성화된 경우 SwiftUI Gesture handler 방식으로 폴백됩니다.")
#endif

                } else {
#if os(iOS)
                    // TODO: 문제 해결되면 삭제할 것. GameController.framework를 완전히 끄면 이 문제는 해결될 것으로 보임
                    Text("참고:\n- 이 방식은 기술적 한계로 인해 드래그 동작 (마우스 버튼을 누른 상태에서 이동)이 부드럽게 동작하지 않을 수 있습니다.")
#endif

                }
                
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
        .frame(minHeight: 720)
        .environmentObject(SettingsStore.shared)
}
