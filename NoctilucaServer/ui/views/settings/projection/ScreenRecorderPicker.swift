//
//  CodecNegotiationPolicyPicker.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import SwiftUI

struct ScreenRecorderPicker: View {
    var body: some View {
        SettingsPicker(selection: .constant(ScreenRecorderType.screenCaptureKit)) {
            ForEach(ScreenRecorderType.allCases, id: \.self) { recorderType in
                SettingsPickerItem(value: recorderType) {
                    Text(recorderType.displayName)
                    Text(recorderType.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(String(localized: "settings.projection.recorder.title", defaultValue: "화면 레코더 선택"))
        }
    }
}
