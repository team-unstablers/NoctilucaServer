//
//  SettingsEntry.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

#if os(iOS)
private struct SettingsPickerUpdateCurrentValueKey: EnvironmentKey {
    static let defaultValue = { (_: AnyHashable?) in }
}

private struct SettingsPickerCurrentValueKey: EnvironmentKey {
    static let defaultValue = AnyHashable?.none
}

fileprivate extension EnvironmentValues {
    var settingsPickerCurrentValue: AnyHashable? {
        get { self[SettingsPickerCurrentValueKey.self] }
        set { self[SettingsPickerCurrentValueKey.self] = newValue }
    }
    var settingsPickerUpdateCurrentValue: ((AnyHashable?) -> Void) {
        get { self[SettingsPickerUpdateCurrentValueKey.self] }
        set { self[SettingsPickerUpdateCurrentValueKey.self] = newValue }
    }
}
#endif


struct SettingsPickerItem<Value: Hashable, Content: View>: View {
    let value: Value
    let content: () -> Content
    
    init(value: Value, @ViewBuilder content: @escaping () -> Content) {
        self.value = value
        self.content = content
    }

#if os(iOS)
    @Environment(\.settingsPickerCurrentValue)
    private var currentValue: AnyHashable?
    
    @Environment(\.settingsPickerUpdateCurrentValue)
    private var updateCurrentValue

    var selected: Bool {
        if let currentValue {
            return currentValue == AnyHashable(self.value)
        } else {
            return false
        }
    }
    
    @ViewBuilder
    var circle: some View {
        if selected {
            Circle()
                .fill(.tint)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                }
        } else {
            Circle()
                .fill(.gray.opacity(0.5))
                .frame(width: 18, height: 18)
        }
            
    }
    
    var body: some View {
        Button {
            updateCurrentValue(AnyHashable(self.value))
        } label: {
            HStack(spacing: 12) {
                self.circle
                VStack(alignment: .leading) {
                    content()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
#elseif os(macOS)
    var body: some View {
        VStack(alignment: .leading) {
            content()
        }
        .tag(value)
    }
#endif
}


struct SettingsPicker<Value: Hashable, Content: View, HeaderContent: View>: View {
    @Binding
    var selection: Value
    
    let content: () -> Content
    let label: () -> HeaderContent
    
    init(selection: Binding<Value>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> HeaderContent) {
        self._selection = selection
        
        self.content = content
        self.label = label
    }
    
#if os(iOS)
    var body: some View {
        VStack(alignment: .leading) {
            label()
        }
        
        content()
            .environment(\.settingsPickerCurrentValue, self.selection)
            .environment(\.settingsPickerUpdateCurrentValue) { newValue in
                if let newValue = newValue as? Value {
                    self.selection = newValue
                }
            }
    }
#elseif os(macOS)
    var body: some View {
        Picker(selection: $selection) {
            content()
        } label: {
            label()
        }
        .pickerStyle(.inline)
    }
#endif
}

#Preview {
    @Previewable
    @State
    var selection: String = "GameController"
    
    Form {
        Section {
            SettingsPicker(selection: $selection) {
                SettingsPickerItem(value: "GameController") {
                    Text("GameController.framework")
                    Text("Apple의 게임 컨트롤러 프레임워크를 사용합니다.\nApp 전환 (⌘Tab), 창 닫기(⌘W), App 종료(⌘Q) 등의 단축키가 동작하지 않을 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                SettingsPickerItem(value: "CocoaEventTap") {
                    Text("Cocoa Event Tap")
                    Text("macOS의 Cocoa Event Tap API를 사용하여 입력을 리디렉션합니다.\n모든 단축키가 정상적으로 동작하지만, 접근성 / 손쉬운 사용 권한을 필요로 합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("입력 리디렉션 방법")
                Text("키보드, 마우스 등의 입력 장치를 원격 컴퓨터로 리디렉션하는 방법을 설정합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("키보드 입력 설정")
            Text("키보드 입력과 관련된 설정을 구성합니다.")
        }
    }
    .formStyle(.grouped)
}
