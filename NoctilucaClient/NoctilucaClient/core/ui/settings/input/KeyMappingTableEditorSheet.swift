//
//  KeyMappingTableEditorSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import SwiftUI

import SiriusKitClient

enum KeyDisplayMode: Hashable {
    case appleStyle
    case generic
}

struct KeyMappingRule {
    var fromKey: LinuxKeycode
    var toKey: LinuxKeycode
}

extension LinuxKeycode {
    var appleDescription: String? {
        switch self {
        case .KEY_ESC:
            return "Escape"
        case .KEY_LEFTCTRL:
            return "Control (Left)"
        case .KEY_RIGHTCTRL:
            return "Control (Right)"
        case .KEY_LEFTMETA:
            return "Command (Left)"
        case .KEY_RIGHTMETA:
            return "Command (Right)"
        case .KEY_LEFTALT:
            return "Option (Left)"
        case .KEY_RIGHTALT:
            return "Option (Right)"
        case .KEY_DELETE:
            // 정방향 딜리트
            return "Forward Delete"
        case .KEY_BACKSPACE:
            // 백스페이스 (역방향 딜리트)
            return "Delete (Backspace)"
        case .KEY_ENTER:
            return "Enter / Return"
            
        default:
            return nil
        }
    }
    
    var appleSymbol: String? {
        switch self {
        case .KEY_ESC:
            return "⎋"
        case .KEY_LEFTCTRL, .KEY_RIGHTCTRL:
            return "⌃"
        case .KEY_LEFTMETA, .KEY_RIGHTMETA:
            return "⌘"
        case .KEY_LEFTALT, .KEY_RIGHTALT:
            return "⌥"
        case .KEY_LEFTSHIFT, .KEY_RIGHTSHIFT:
            return "⇧"
        case .KEY_DELETE:
            // 정방향 딜리트
            return "⌦"
        case .KEY_BACKSPACE:
            // 백스페이스 (역방향 딜리트)
            return "⌫"
        case .KEY_CAPSLOCK:
            return "⇪"
        case .KEY_LEFT:
            return "←"
        case .KEY_RIGHT:
            return "→"
        case .KEY_UP:
            return "↑"
        case .KEY_DOWN:
            return "↓"
        case .KEY_ENTER:
            return "⌤"
        case .KEY_PAGEUP:
            return "⇞"
        case .KEY_PAGEDOWN:
            return "⇟"
        case .KEY_TAB:
            return "⇥"
        case .KEY_END:
            return "↘"
        case .KEY_HOME:
            return "↖"
        case .KEY_SPACE:
            return "␣"
            
        case .KEY_HANGEUL, .KEY_HANGUEL:
            return "한"
        case .KEY_KATAKANAHIRAGANA:
            return "かな"
        case .KEY_MUHENKAN:
            return "英数"
            
        default:
            return self.genericSymbol
        }
    }
    
    var genericSymbol: String? {
        switch self {
        case .KEY_ESC:
            return "Esc"
        case .KEY_LEFTCTRL, .KEY_RIGHTCTRL:
            return "Ctrl"
        case .KEY_LEFTMETA, .KEY_RIGHTMETA:
            return "Super"
        case .KEY_LEFTALT, .KEY_RIGHTALT:
            return "Alt"
        case .KEY_DELETE:
            // 정방향 딜리트
            return "Delete"
        case .KEY_BACKSPACE:
            // 백스페이스 (역방향 딜리트)
            return "Backspace"
        case .KEY_CAPSLOCK:
            return "Caps Lock"
        case .KEY_LEFT:
            return "←"
        case .KEY_RIGHT:
            return "→"
        case .KEY_UP:
            return "↑"
        case .KEY_DOWN:
            return "↓"
        case .KEY_ENTER:
            return "Enter"
        case .KEY_PAGEUP:
            return "PgUp"
        case .KEY_PAGEDOWN:
            return "PgDn"
        case .KEY_TAB:
            return "Tab"
        case .KEY_END:
            return "End"
        case .KEY_HOME:
            return "Home"
        case .KEY_SPACE:
            return "Space"
            
        case .KEY_HANGEUL, .KEY_HANGUEL:
            return "한"
        case .KEY_HENKAN:
            return "変換"
        case .KEY_MUHENKAN:
            return "無変換"
        case .KEY_KATAKANAHIRAGANA:
            return "かな"
            
        default:
            return nil
        }
    }
}

fileprivate struct KeycodeView: View {
    let keycode: LinuxKeycode
    let displayMode: KeyDisplayMode
    
    var body: some View {
        let symbol = if displayMode == .appleStyle {
            keycode.appleSymbol
        } else {
            keycode.genericSymbol
        }
        
        if let symbol = symbol {
            let description = if displayMode == .appleStyle {
                keycode.appleDescription ?? keycode.description
            } else {
                keycode.description
            }
            VStack {
                Text("\(symbol)")
                    .font(.title)
                Text("\(description)")
                    .font(.caption)
            }
            .frame(width: 128)
            .background(.red)
        } else {
            Text("\(keycode.description)")
                .font(.title)
                .frame(width: 128)
                .background(.red)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .allowsTightening(true)
        }
    }
    
}

struct KeyMappingTableItemView: View {
    let rule: KeyMappingRule
    
    let fromKeyDisplayMode: KeyDisplayMode
    let toKeyDisplayMode: KeyDisplayMode
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            KeycodeView(keycode: rule.fromKey, displayMode: fromKeyDisplayMode)
            Spacer()
            Text("→")
                .font(.largeTitle)
            Spacer()
            KeycodeView(keycode: rule.toKey, displayMode: toKeyDisplayMode)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.gray.mix(with: .white, by: 0.9))
        .clipShape(.rect(cornerRadius: 8))
        .padding(.bottom, 12)
    }
}

struct KeyMappingTableEditorSheet: View {
    @Environment(\.dismiss)
    private var dismiss
    
    @State
    var fromKeyDisplayMode: KeyDisplayMode = .appleStyle
    
    @State
    var toKeyDisplayMode: KeyDisplayMode = .appleStyle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(markdown: String(localized: "settings.input.key_mapping.editor.title", defaultValue: "키매핑 테이블 편집기"))
                        .font(.headline)
                        .padding(.bottom, 4)
                        .foregroundStyle(.primary)
                    Text("description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }
                
                Spacer()
                
                HStack {
                    Picker(selection: $fromKeyDisplayMode) {
                        Text(markdown: String(localized: "settings.input.key_mapping.display_mode.apple", defaultValue: "Apple 스타일")).tag(KeyDisplayMode.appleStyle)
                        Text(markdown: String(localized: "settings.input.key_mapping.display_mode.generic", defaultValue: "일반 스타일")).tag(KeyDisplayMode.generic)
                    } label: {
                        Text(markdown: String(localized: "settings.input.key_mapping.display_mode.label", defaultValue: "키 표시 방식"))
                    }
                    Picker(selection: $toKeyDisplayMode) {
                        Text(markdown: String(localized: "settings.input.key_mapping.display_mode.apple", defaultValue: "Apple 스타일")).tag(KeyDisplayMode.appleStyle)
                        Text(markdown: String(localized: "settings.input.key_mapping.display_mode.generic", defaultValue: "일반 스타일")).tag(KeyDisplayMode.generic)
                    } label: {
                        Text("→")
                    }
                }
                
            }
            
            VStack(alignment: .leading, spacing: 0) {
                KeyMappingTableItemView(
                    rule: .init(fromKey: .KEY_LEFTCTRL, toKey: .KEY_LEFTMETA),
                    fromKeyDisplayMode: fromKeyDisplayMode,
                    toKeyDisplayMode: toKeyDisplayMode
                )
                KeyMappingTableItemView(
                    rule: .init(fromKey: .KEY_KATAKANAHIRAGANA, toKey: .KEY_HANGEUL),
                    fromKeyDisplayMode: fromKeyDisplayMode,
                    toKeyDisplayMode: toKeyDisplayMode
                )
            }
            .padding(.bottom, 12)
            
            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "취소"), role: .cancel) {
                }
                .keyboardShortcut(.escape)
                Button(String(localized: "common.confirm", defaultValue: "확인"), role: .compatibleConfirm) {
                }
            }
        }
        .padding(24)
    }
}


#Preview {
    KeyMappingTableEditorSheet()
}
