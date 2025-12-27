//
//  MouseRedirectionMethodPicker.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/27/25.
//

import SwiftUI

struct KeyboardRedirectionMethodPicker: View {
    @Binding
    var input: AppSettings.Input
    
    var body: some View {
        SettingsPicker(selection: $input.redirectionMethod) {
            SettingsPickerItem(value: AppSettings.InputRedirectionMethod.gameController) {
                Text("GameController.framework")
                Text("Apple의 게임 컨트롤러 프레임워크를 사용합니다.\nApp 전환 (⌘Tab), 창 닫기(⌘W), App 종료(⌘Q) 등의 단축키가 동작하지 않을 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            SettingsPickerItem(value: AppSettings.InputRedirectionMethod.cocoaEventTap) {
#if os(macOS)
                Text("Cocoa Event Tap")
#else
                Text("Cocoa Event Tap (이 플랫폼에서는 사용할 수 없습니다)")
#endif
                Text("macOS의 Cocoa Event Tap API를 사용하여 입력을 리디렉션합니다.\n모든 단축키가 정상적으로 동작하지만, 입력 모니터링 권한을 필요로 합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
#if os(iOS)
            .disabled(true)
#endif
        } label: {
            Text("입력 리디렉션 방법")
            Text("키보드 입력을 원격 컴퓨터로 리디렉션하는 방법을 설정합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
