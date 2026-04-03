//
//  KeyboardGridView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import SwiftUI

import SiriusKitCore

/// US 104키 레이아웃의 간단한 그리드 시각화.
/// 각 키를 논리적 행/열로 배치하고, 눌린 키를 하이라이트합니다.
struct KeyboardGridView: View {
    let pressedKeys: Set<LinuxKeycode>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 0: Function keys
            keyRow(functionRow)
            Divider().padding(.vertical, 2)
            // Row 1: Number row
            keyRow(numberRow)
            // Row 2: QWERTY row
            keyRow(qwertyRow)
            // Row 3: Home row
            keyRow(homeRow)
            // Row 4: Shift row
            keyRow(shiftRow)
            // Row 5: Bottom row
            keyRow(bottomRow)
        }
        .padding(4)
    }

    private func keyRow(_ keys: [KeyDef]) -> some View {
        HStack(spacing: 1) {
            ForEach(keys) { key in
                keyCell(key)
            }
        }
    }

    private func keyCell(_ key: KeyDef) -> some View {
        let isPressed = pressedKeys.contains(key.keycode)
        return Text(key.label)
            .font(.system(size: 8, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: key.width, height: 20)
            .background(isPressed ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isPressed ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Key Definition

private struct KeyDef: Identifiable {
    let id: UInt16
    let label: String
    let keycode: LinuxKeycode
    let width: CGFloat

    init(_ label: String, _ keycode: LinuxKeycode, width: CGFloat = 22) {
        self.id = keycode.rawValue
        self.label = label
        self.keycode = keycode
        self.width = width
    }
}

// MARK: - US 104 Layout Data

private let functionRow: [KeyDef] = [
    .init("Esc", .KEY_ESC),
    .init("F1", .KEY_F1), .init("F2", .KEY_F2), .init("F3", .KEY_F3), .init("F4", .KEY_F4),
    .init("F5", .KEY_F5), .init("F6", .KEY_F6), .init("F7", .KEY_F7), .init("F8", .KEY_F8),
    .init("F9", .KEY_F9), .init("F10", .KEY_F10), .init("F11", .KEY_F11), .init("F12", .KEY_F12),
    .init("PrSc", .KEY_SYSRQ), .init("SLk", .KEY_SCROLLLOCK), .init("Pse", .KEY_PAUSE),
]

private let numberRow: [KeyDef] = [
    .init("`", .KEY_GRAVE),
    .init("1", .KEY_1), .init("2", .KEY_2), .init("3", .KEY_3), .init("4", .KEY_4),
    .init("5", .KEY_5), .init("6", .KEY_6), .init("7", .KEY_7), .init("8", .KEY_8),
    .init("9", .KEY_9), .init("0", .KEY_0),
    .init("-", .KEY_MINUS), .init("=", .KEY_EQUAL),
    .init("BS", .KEY_BACKSPACE, width: 34),
]

private let qwertyRow: [KeyDef] = [
    .init("Tab", .KEY_TAB, width: 30),
    .init("Q", .KEY_Q), .init("W", .KEY_W), .init("E", .KEY_E), .init("R", .KEY_R),
    .init("T", .KEY_T), .init("Y", .KEY_Y), .init("U", .KEY_U), .init("I", .KEY_I),
    .init("O", .KEY_O), .init("P", .KEY_P),
    .init("[", .KEY_LEFTBRACE), .init("]", .KEY_RIGHTBRACE),
    .init("\\", .KEY_BACKSLASH, width: 26),
]

private let homeRow: [KeyDef] = [
    .init("Caps", .KEY_CAPSLOCK, width: 34),
    .init("A", .KEY_A), .init("S", .KEY_S), .init("D", .KEY_D), .init("F", .KEY_F),
    .init("G", .KEY_G), .init("H", .KEY_H), .init("J", .KEY_J), .init("K", .KEY_K),
    .init("L", .KEY_L),
    .init(";", .KEY_SEMICOLON), .init("'", .KEY_APOSTROPHE),
    .init("Enter", .KEY_ENTER, width: 40),
]

private let shiftRow: [KeyDef] = [
    .init("LShift", .KEY_LEFTSHIFT, width: 44),
    .init("Z", .KEY_Z), .init("X", .KEY_X), .init("C", .KEY_C), .init("V", .KEY_V),
    .init("B", .KEY_B), .init("N", .KEY_N), .init("M", .KEY_M),
    .init(",", .KEY_COMMA), .init(".", .KEY_DOT), .init("/", .KEY_SLASH),
    .init("RShift", .KEY_RIGHTSHIFT, width: 50),
]

private let bottomRow: [KeyDef] = [
    .init("LCtl", .KEY_LEFTCTRL, width: 30),
    .init("LMeta", .KEY_LEFTMETA, width: 28),
    .init("LAlt", .KEY_LEFTALT, width: 28),
    .init("Space", .KEY_SPACE, width: 120),
    .init("RAlt", .KEY_RIGHTALT, width: 28),
    .init("RMeta", .KEY_RIGHTMETA, width: 28),
    .init("Menu", .KEY_MENU, width: 28),
    .init("RCtl", .KEY_RIGHTCTRL, width: 30),
]
