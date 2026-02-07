//
//  HIDIOUIKitKeyboardView.swift
//  NoctilucaClient
//
//  Created by Codex on 12/31/25.
//

#if os(iOS)

import SwiftUI
import UIKit

import SiriusKitClient

struct HIDIOUIKitKeyboardInputHost: View {
    let client: NoctilucaClient
    
    @ObservedObject
    var keyboard: HIDIOUIKitKeyboard
    
    @Binding
    var isPresented: Bool

    var body: some View {
        ZStack {
            Color.clear
            HIDIOUIKitKeyboardInputView(
                isFirstResponder: $isPresented,
                onInsertText: { text in
                    keyboard.handleInsertText(text)
                },
                onDeleteBackward: {
                    keyboard.handleDeleteBackward()
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateConnection(isEnabled: isPresented)
        }
        .onDisappear {
            updateConnection(isEnabled: false)
        }
        .onChange(of: isPresented) { _, newValue in
            updateConnection(isEnabled: newValue)
            if !newValue {
                keyboard.resetModifiers()
            }
        }
    }

    private func updateConnection(isEnabled: Bool) {
        guard let controller = client.hidioChannel.controller else {
            return
        }

        if isEnabled {
            controller.connect(keyboard)
        } else {
            controller.disconnect(.uiKitKeyboard)
            keyboard.resetModifiers()
        }
    }
}

struct HIDIOUIKitKeyboardHelperView: View {
    @ObservedObject var keyboard: HIDIOUIKitKeyboard
    let isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        modifierToggle(label: "Ctrl", keyCode: .KEY_LEFTCTRL)
                        modifierToggle(label: "Opt", keyCode: .KEY_LEFTALT)
                        modifierToggle(label: "Cmd", keyCode: .KEY_LEFTMETA)
                        modifierToggle(label: "Shift", keyCode: .KEY_LEFTSHIFT)

                        // TODO: ESC / Home / End / PgUp / PgDn 등의 추가 버튼을 지원한다.
                        actionButton(label: "Tab") {
                            keyboard.sendKey(.KEY_TAB)
                        }

                        actionButton(label: "Left") {
                            keyboard.sendKey(.KEY_LEFT)
                        }
                        actionButton(label: "Down") {
                            keyboard.sendKey(.KEY_DOWN)
                        }
                        actionButton(label: "Up") {
                            keyboard.sendKey(.KEY_UP)
                        }
                        actionButton(label: "Right") {
                            keyboard.sendKey(.KEY_RIGHT)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
        }
    }

    private func modifierToggle(label: String, keyCode: LinuxKeycode) -> some View {
        let isActive = keyboard.isModifierActive(keyCode)

        return Button {
            keyboard.toggleModifier(keyCode)
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .frame(minWidth: 36, minHeight: 32)
                .padding(.horizontal, 4)
        }
        .buttonStyle(HIDIOUIKitKeyboardKeyButtonStyle(isActive: isActive))
    }

    private func actionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 36, minHeight: 32)
                .padding(.horizontal, 4)
        }
        .buttonStyle(HIDIOUIKitKeyboardKeyButtonStyle(isActive: false))
    }
}

private struct HIDIOUIKitKeyboardKeyButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color(.systemGray4)
        }
        return isActive ? Color.accentColor.opacity(0.2) : Color(.systemGray5)
    }
}

final class HIDIOUIKitKeyboardTextField: UITextField {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func deleteBackward() {
        if markedTextRange == nil {
            onDeleteBackward?()
        }
        super.deleteBackward()
    }
}

struct HIDIOUIKitKeyboardInputView: UIViewRepresentable {
    @Binding var isFirstResponder: Bool
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isFirstResponder: $isFirstResponder,
            onInsertText: onInsertText,
            onDeleteBackward: onDeleteBackward
        )
    }

    func makeUIView(context: Context) -> HIDIOUIKitKeyboardTextField {
        let textField = HIDIOUIKitKeyboardTextField()
        textField.onInsertText = onInsertText
        textField.onDeleteBackward = onDeleteBackward
        textField.delegate = context.coordinator

        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.returnKeyType = .default
        textField.enablesReturnKeyAutomatically = false
        textField.backgroundColor = .clear
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.text = ""
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.textContentType = .none

        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldEditingChanged(_:)),
            for: .editingChanged
        )

        return textField
    }

    func updateUIView(_ uiView: HIDIOUIKitKeyboardTextField, context: Context) {
        if isFirstResponder {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var isFirstResponder: Bool
        let onInsertText: (String) -> Void
        let onDeleteBackward: () -> Void

        init(
            isFirstResponder: Binding<Bool>,
            onInsertText: @escaping (String) -> Void,
            onDeleteBackward: @escaping () -> Void
        ) {
            _isFirstResponder = isFirstResponder
            self.onInsertText = onInsertText
            self.onDeleteBackward = onDeleteBackward
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFirstResponder {
                DispatchQueue.main.async {
                    self.isFirstResponder = true
                }
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // 포커스 해제 전에 남아있는 확정 텍스트를 전송
            if textField.markedTextRange == nil,
               let text = textField.text, !text.isEmpty {
                onInsertText(text)
                textField.text = ""
            }

            if isFirstResponder {
                DispatchQueue.main.async {
                    self.isFirstResponder = false
                }
            }
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            // IME 조합 중에는 시스템이 텍스트를 관리하도록 허용
            if textField.markedTextRange != nil {
                return true
            }

            // 삭제는 HIDIOUIKitKeyboardTextField.deleteBackward()에서 처리
            if string.isEmpty {
                return true
            }

            // 확정된 텍스트를 직접 처리 (ASCII → keycodes, 비-ASCII → ucs4)
            onInsertText(string)
            return false
        }

        /// IME 조합 완료 후 텍스트 필드에 남아있는 확정 텍스트를 추출하여 전송
        @objc func textFieldEditingChanged(_ textField: UITextField) {
            guard textField.markedTextRange == nil else {
                return
            }

            guard let text = textField.text, !text.isEmpty else {
                return
            }

            onInsertText(text)
            textField.text = ""
        }
    }
}

#endif
