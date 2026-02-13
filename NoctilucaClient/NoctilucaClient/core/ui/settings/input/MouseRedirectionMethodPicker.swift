//
//  MouseRedirectionMethodPicker.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/27/25.
//

import SwiftUI

struct MouseRedirectionMethodPicker: View {
    @Binding
    var input: AppSettings.Input
    
    var body: some View {
#if os(iOS)
        VStack(alignment: .leading, spacing: 24) {
            SettingsPicker(selection: $input.pointerInputMode) {
                SettingsPickerItem(value: AppSettings.PointerInputMode.automatic) {
                    Text("자동 전환 (권장)")
                    Text("하드웨어 마우스가 연결되면 자동으로 전환하고, 연결이 해제되면 터치 포인터로 복귀합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                SettingsPickerItem(value: AppSettings.PointerInputMode.touchPointer) {
                    Text("터치 포인터만 사용")
                    Text("터치 제스처만으로 포인터를 조작합니다. 하드웨어 마우스 입력은 무시됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                SettingsPickerItem(value: AppSettings.PointerInputMode.hardwareMouse) {
                    Text("하드웨어 마우스 우선")
                    Text("가능한 경우 하드웨어 마우스를 우선 사용합니다. 하드웨어 마우스가 연결되어 있는 동안 터치 입력은 무시됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("포인터 입력 모드")
                Text("터치 입력과 하드웨어 마우스 입력 중 어떤 소스를 사용할지 결정합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SettingsPicker(selection: $input.touchInputMode) {
                SettingsPickerItem(value: AppSettings.TouchInputMode.touch) {
                    Text("터치 모드 (기본)")
                    Text("터치 위치가 곧 커서 위치가 됩니다. 탭은 이동+클릭, 드래그는 클릭+드래그로 처리합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                SettingsPickerItem(value: AppSettings.TouchInputMode.trackpad) {
                    Text("트랙패드 모드")
                    Text("상대 좌표로 커서를 이동합니다. 긴 누름 또는 두 손가락 조합으로 드래그합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("터치 입력 모드")
                Text("터치 제스처를 어떤 방식으로 마우스 동작에 매핑할지 설정합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
#endif
    }
}
