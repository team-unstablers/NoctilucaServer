import SwiftUI

struct ProjectionSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsPicker(selection: $settingsStore.settings.input.redirectionMethod) {
                    SettingsPickerItem(value: AppSettings.InputRedirectionMethod.gameController) {
                        Text("GameController.framework")
                        Text("Apple의 게임 컨트롤러 프레임워크를 사용합니다.\nApp 전환 (⌘Tab), 창 닫기(⌘W), App 종료(⌘Q) 등의 단축키가 동작하지 않을 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: AppSettings.InputRedirectionMethod.cocoaEventTap) {
                        Text("Cocoa Event Tap")
                        Text("macOS의 Cocoa Event Tap API를 사용하여 입력을 리디렉션합니다.\n모든 단축키가 정상적으로 동작하지만, 접근성 / 손쉬운 사용 권한을 필요로 합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
#if os(iOS)
                    .disabled(true)
#endif
                } label: {
                    Text("입력 리디렉션 방법")
                    Text("키보드, 마우스 등의 입력 장치를 원격 컴퓨터로 리디렉션하는 방법을 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("기본 입력 설정")
            }
            
            Section {
                VStack(alignment: .leading) {
                    Text("보조 키 오버라이드")
                    Text("각 보조 키가 원격 컴퓨터에서 어떤 키로 인식될지 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker(selection: $settingsStore.settings.input.modifierKeyOverrides.capsLock) {
                    Text("⇪ (Caps Lock)")
                        .tag(AppSettings.ModifierKeyOverride.capsLock)
                    
                    Text("⌃ (Control)")
                        .tag(AppSettings.ModifierKeyOverride.control)
                                            
                    Text("⌥ (Option)")
                        .tag(AppSettings.ModifierKeyOverride.option)
                    
                    Text("⌘ (Command)")
                        .tag(AppSettings.ModifierKeyOverride.command)
                    
                    Text("fn (Function)")
                        .tag(AppSettings.ModifierKeyOverride.function)

                    Text("⎋ (Escape)")
                        .tag(AppSettings.ModifierKeyOverride.escape)
                    
                    Text("비활성화")
                        .tag(AppSettings.ModifierKeyOverride.disabled)
                } label: {
                    Text("Caps Lock(⇪) 키")
                }

                Picker(selection: $settingsStore.settings.input.modifierKeyOverrides.control) {
                    Text("⇪ (Caps Lock)")
                        .tag(AppSettings.ModifierKeyOverride.capsLock)
                    
                    Text("⌃ (Control)")
                        .tag(AppSettings.ModifierKeyOverride.control)
                                            
                    Text("⌥ (Option)")
                        .tag(AppSettings.ModifierKeyOverride.option)
                    
                    Text("⌘ (Command)")
                        .tag(AppSettings.ModifierKeyOverride.command)
                    
                    Text("fn (Function)")
                        .tag(AppSettings.ModifierKeyOverride.function)

                    Text("⎋ (Escape)")
                        .tag(AppSettings.ModifierKeyOverride.escape)
                    
                    Text("비활성화")
                        .tag(AppSettings.ModifierKeyOverride.disabled)
                } label: {
                    Text("Control(⌃) 키")
                }
                Picker(selection: $settingsStore.settings.input.modifierKeyOverrides.option) {
                    Text("⇪ (Caps Lock)")
                        .tag(AppSettings.ModifierKeyOverride.capsLock)
                    
                    Text("⌃ (Control)")
                        .tag(AppSettings.ModifierKeyOverride.control)
                                            
                    Text("⌥ (Option)")
                        .tag(AppSettings.ModifierKeyOverride.option)
                    
                    Text("⌘ (Command)")
                        .tag(AppSettings.ModifierKeyOverride.command)
                    
                    Text("fn (Function)")
                        .tag(AppSettings.ModifierKeyOverride.function)

                    Text("⎋ (Escape)")
                        .tag(AppSettings.ModifierKeyOverride.escape)
                    
                    Text("비활성화")
                        .tag(AppSettings.ModifierKeyOverride.disabled)
                } label: {
                    Text("Option(⌥) 키")
                }
                Picker(selection: $settingsStore.settings.input.modifierKeyOverrides.command) {
                    Text("⇪ (Caps Lock)")
                        .tag(AppSettings.ModifierKeyOverride.capsLock)
                    
                    Text("⌃ (Control)")
                        .tag(AppSettings.ModifierKeyOverride.control)
                                            
                    Text("⌥ (Option)")
                        .tag(AppSettings.ModifierKeyOverride.option)
                    
                    Text("⌘ (Command)")
                        .tag(AppSettings.ModifierKeyOverride.command)
                    
                    Text("fn (Function)")
                        .tag(AppSettings.ModifierKeyOverride.function)

                    Text("⎋ (Escape)")
                        .tag(AppSettings.ModifierKeyOverride.escape)
                    
                    Text("비활성화")
                        .tag(AppSettings.ModifierKeyOverride.disabled)
                } label: {
                    Text("Command(⌘) 키")
                }
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
                SettingsPicker(selection: $settingsStore.settings.input.mouseMoveMode) {
                    SettingsPickerItem(value: AppSettings.MouseMoveMode.absolute) {
                        Text("절대 좌표 모드")
                        Text("절대 좌표를 사용하여 마우스 위치를 지정합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: AppSettings.MouseMoveMode.relative) {
                        Text("상대 좌표 모드")
                        Text("상대 좌표를 사용하여 마우스 위치를 지정합니다.\n게임 스트리밍 등 특수한 케이스에서 도움이 될 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("마우스 이동 모드")
                    Text("마우스 이동에 사용할 좌표 모드를 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("마우스 입력 설정")
                Text("마우스 입력과 관련된 설정을 구성합니다.")
            }
            
            Section {
                Toggle(isOn: $settingsStore.settings.input.invertMouseButtons) {
                    Text("마우스 버튼 위치를 반전하기")
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
                // FIXME: 숫자 입력 필드로 변경
                
                /*
                
                 */
                SettingsEntry(title: "마우스 스크롤 배수", subtitle: "마우스 스크롤에 배수 값을 적용하여 전송합니다.\n값이 클수록 스크롤 속도가 빨라집니다.") {
                    Slider(value: $settingsStore.settings.input.mouseScrollMultiplier, in: 0.5...1.5, step: 0.25) {
                        
                    } minimumValueLabel: {
                        Text("0.5x")
                    } maximumValueLabel: {
                        Text("1.5x")
                    }
                }
                
                SettingsEntry(title: "뭔가 잘못 건드려서 망가졌어요", subtitle: "이 버튼을 누르면 입력 관련 설정이 초기화됩니다.") {
                    Button("입력 관련 설정 초기화") {
                        settingsStore.resetInputSettings()
                    }
                }
            } header: {
                Text("고급 설정")
                Text("입력 관련 고급 설정을 구성합니다.")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ProjectionSettingsTab()
        .frame(minHeight: 720)
        .environmentObject(SettingsStore())
}
