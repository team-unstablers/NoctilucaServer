//
//  SettingsPicker.swift
//  NoctilucaServer
//

import SwiftUI

struct SettingsPickerItem<Value: Hashable, Content: View>: View {
    let value: Value
    let content: () -> Content

    init(value: Value, @ViewBuilder content: @escaping () -> Content) {
        self.value = value
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading) {
            content()
        }
        .tag(value)
    }
}

struct SettingsPicker<Value: Hashable, Content: View, HeaderContent: View>: View {
    @Binding var selection: Value
    let content: () -> Content
    let label: () -> HeaderContent

    init(selection: Binding<Value>,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder label: @escaping () -> HeaderContent) {
        self._selection = selection
        self.content = content
        self.label = label
    }

    var body: some View {
        Picker(selection: $selection) {
            content()
        } label: {
            label()
        }
        .pickerStyle(.inline)
    }
}
