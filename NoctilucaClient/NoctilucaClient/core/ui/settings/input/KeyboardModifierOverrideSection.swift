//
//  MouseRedirectionMethodPicker.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/27/25.
//

import SwiftUI

struct KeyboardModifierOverrideSection: View {
    @Binding
    var input: AppSettings.Input
    
    @ViewBuilder
    var pickerBody: some View {
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
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("보조 키 오버라이드")
            Text("각 보조 키가 원격 컴퓨터에서 다르게 동작하도록 설정합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        
        Picker(selection: $input.modifierKeyOverrides.capsLock) {
            pickerBody
        } label: {
            Text("Caps Lock(⇪) 키")
        }
        
        Picker(selection: $input.modifierKeyOverrides.control) {
            pickerBody
        } label: {
            Text("Control(⌃) 키")
        }
        
        Picker(selection: $input.modifierKeyOverrides.option) {
            pickerBody
        } label: {
            Text("Option(⌥) 키")
        }
        
        Picker(selection: $input.modifierKeyOverrides.command) {
            pickerBody
        } label: {
            Text("Command(⌘) 키")
        }
    }
}
