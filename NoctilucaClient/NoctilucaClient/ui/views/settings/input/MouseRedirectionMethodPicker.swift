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
        // TODO: mouseMoveMode가 아니라 mouseRedirectionMethod 등으로 바꿔야 함
        SettingsPicker(selection: $input.mouseMoveMode) {
            SettingsPickerItem(value: AppSettings.MouseMoveMode.relative) {
                Text("GameController.framework를 보조하여 사용 **(권장)**")
                Text("가능한 경우 Apple의 게임 컨트롤러 프레임워크를 보조 수단을 사용합니다.\n마우스 이동에는 **상대 좌표** 방식을 사용하며, 더 많은 마우스 버튼을 지원합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                

                
                /*
                if DeviceKind.current != .iPad {
                    Text("상대 좌표 모드")
                    Text("상대 좌표를 사용하여 마우스 위치를 지정합니다.\n게임 스트리밍 등 특수한 케이스에서 도움이 될 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("상대 좌표 모드")
                    Text("상대 좌표를 사용하여 마우스 위치를 지정합니다.\n게임 스트리밍 등 특수한 케이스에서 도움이 될 수 있습니다.\n**참고: iPad에서는 멀티 태스킹이 활성화된 경우 절대 좌표 모드로 폴백됩니다.**")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                 */
            }
            
            SettingsPickerItem(value: AppSettings.MouseMoveMode.absolute) {
                Text("SwiftUI Gesture handler만 사용")
                Text("SwiftUI의 제스쳐 핸들러를 통해 마우스 입력을 수집합니다.\n마우스 이동에는 **절대 좌표** 방식을 사용하며, 기본적인 마우스 버튼만 지원합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                /*
                Text("절대 좌표 모드")
                Text("절대 좌표를 사용하여 마우스 위치를 지정합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                 */
            }
        } label: {
            Text("입력 리디렉션 방법")
            HStack {
                Text("마우스 입력을 원격 컴퓨터로 리디렉션하는 방법을 설정합니다. [더 알아보기…](https://google.com)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            /*
            Text("마우스 이동 모드")
            Text("마우스 이동에 사용할 좌표 모드를 설정합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
             */
        }
    }
}
