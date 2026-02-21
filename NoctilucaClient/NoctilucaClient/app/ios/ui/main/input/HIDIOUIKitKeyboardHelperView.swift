//
//  HIDIOUIKitKeyboardHelperView.swift
//  NoctilucaClient
//

#if os(iOS)

import SwiftUI
import UIKit

import SiriusKitClient

struct HIDIOUIKitKeyboardHelperView: View {
    @ObservedObject
    var keyboard: HIDIOUIKitKeyboard
    let isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 8) {
                Divider()
                HStack(spacing: 12) {
                    actionButton(label: "esc", keyCode: .KEY_ESC)
                        .frame(width: 112)

                    actionButton(label: "tab", symbol: "⇥", keyCode: .KEY_TAB)
                        .frame(width: 112)

                    Spacer()

                    actionButton(label: "delete", symbol: "⌫", keyCode: .KEY_BACKSPACE)
                        .frame(width: 112)
                }
                    .padding(.horizontal, 12)
                HStack(spacing: 12) {
                    actionButton(
                        label: "control",
                        symbol: "^",
                        keyCode: .KEY_LEFTCTRL
                    )
                        .frame(width: 72)
                    actionButton(
                        label: "option",
                        symbol: "⌥",
                        keyCode: .KEY_LEFTALT
                    )
                        .frame(width: 72)
                    actionButton(
                        label: "command",
                        symbol: "⌘",
                        keyCode: .KEY_LEFTMETA
                    )
                        .frame(width: 96)

                    actionButton(
                        label: "shift",
                        symbol: "⇧",
                        keyCode: .KEY_LEFTSHIFT
                    )
                        .frame(width: 112)

                    Spacer()

                    HStack(alignment: .bottom) {
                        directionalButton(label: "←", keyCode: .KEY_LEFT)
                            .frame(width: 72)
                        VStack {
                            directionalButton(label: "↑", keyCode: .KEY_UP)
                                .frame(width: 72)
                            directionalButton(label: "↓", keyCode: .KEY_DOWN)
                                .frame(width: 72)
                        }
                        directionalButton(label: "→", keyCode: .KEY_RIGHT)
                            .frame(width: 72)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
        }
    }

    private func actionButton(label: String, symbol: String = "", keyCode: LinuxKeycode) -> some View {
        HIDIOUIKitKeyPressButton(
            onPress: { keyboard.keyDown(keyCode) },
            onRelease: { keyboard.keyUp(keyCode) }
        ) {
            VStack {
                Text(symbol)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer()
                Text(label)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(minWidth: 72, maxHeight: 72)
        }
    }

    private func directionalButton(label: String, keyCode: LinuxKeycode) -> some View {
        HIDIOUIKitKeyPressButton(
            onPress: { keyboard.keyDown(keyCode) },
            onRelease: { keyboard.keyUp(keyCode) }
        ) {
            VStack {
                Text(label)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(8)
            .frame(minWidth: 72, maxHeight: 36)
        }
    }
}

#Preview("HelperView") {
    let keyboard = HIDIOUIKitKeyboard()
    HIDIOUIKitKeyboardHelperView(keyboard: keyboard, isVisible: true)
}

#endif
