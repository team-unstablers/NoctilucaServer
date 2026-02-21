//
//  HIDIOUIKitKeyboardHelperView.swift
//  NoctilucaClient
//

#if os(iOS)

import SwiftUI
import UIKit

import SiriusKitClient

struct HIDIOUIKitKeyboardCompactHelperView: View {
    @ObservedObject
    var keyboard: HIDIOUIKitKeyboard
    let isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 8) {
                Divider()
                HStack(spacing: 12) {
                    actionButton(label: "←", keyCode: .KEY_LEFT)
                    actionButton(label: "↓", keyCode: .KEY_DOWN)
                    actionButton(label: "↑", keyCode: .KEY_UP)
                    actionButton(label: "→", keyCode: .KEY_RIGHT)
                }
                    .padding(.horizontal, 12)
                HStack(spacing: 12) {
                    actionButton(
                        label: "control",
                        symbol: "^",
                        keyCode: .KEY_LEFTCTRL
                    )
                    actionButton(
                        label: "option",
                        symbol: "⌥",
                        keyCode: .KEY_LEFTALT
                    )
                    actionButton(
                        label: "command",
                        symbol: "⌘",
                        keyCode: .KEY_LEFTMETA
                    )

                    actionButton(
                        label: "shift",
                        symbol: "⇧",
                        keyCode: .KEY_LEFTSHIFT
                    )
                    
                    /*

                    Spacer()

                    HStack(alignment: .bottom) {
                            .frame(width: 72)
                        VStack {
                                .frame(width: 72)
                            directionalButton(label: "↓", keyCode: .KEY_DOWN)
                                .frame(width: 72)
                        }
                        directionalButton(label: "→", keyCode: .KEY_RIGHT)
                            .frame(width: 72)
                    }
                     */
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
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
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
    HIDIOUIKitKeyboardCompactHelperView(keyboard: keyboard, isVisible: true)
}

#endif
