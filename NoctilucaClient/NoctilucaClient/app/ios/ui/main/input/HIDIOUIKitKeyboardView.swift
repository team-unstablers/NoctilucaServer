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

struct HIDIOUIKitCJKCompositionPreviewView: View {
    let compositingText: String

    var body: some View {
        VStack(spacing: 0) {
            Text(compositingText)
                .font(.system(size: 18))
                .padding(4)
            HStack {
                Text("스페이스 바 / ↩︎ 키로 확정 — CJK Composition Preview")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .font(.caption2)
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(4)
            }
        }
        .padding(8)
        .frame(minWidth: 160)
        .fixedSize()
        .background(.thinMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

struct HIDIOUIKitKeyboardInputHost: View {
    let client: NoctilucaClient
    
    @ObservedObject
    var keyboard: HIDIOUIKitKeyboard
    
    @Binding
    var isPresented: Bool
    
    @State
    var compositingText: String = ""

    var body: some View {
        ZStack {
            Color.clear
            if !compositingText.isEmpty {
                HIDIOUIKitCJKCompositionPreviewView(compositingText: compositingText)
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                    .zIndex(1)
            }
            HIDIOUIKitKeyboardInputView(
                isFirstResponder: $isPresented,
                compositingText: $compositingText,
                onInsertText: { text in
                    keyboard.handleInsertText(text)
                },
                onDeleteBackward: {
                    keyboard.handleDeleteBackward()
                },
                onReturnKey: {
                    keyboard.handleReturnKey()
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
    @Binding var compositingText: String
    
    init(compositingText: Binding<String>) {
        _compositingText = compositingText
        
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func deleteBackward() {
        if markedTextRange == nil && compositingText.isEmpty {
            onDeleteBackward?()
        }
        super.deleteBackward()
    }
}

struct HIDIOUIKitKeyboardInputView: UIViewRepresentable {
    @Binding var isFirstResponder: Bool
    @Binding var compositingText: String
    
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onReturnKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isFirstResponder: $isFirstResponder,
            compositingText: $compositingText,
            onInsertText: onInsertText,
            onDeleteBackward: onDeleteBackward,
            onReturnKey: onReturnKey
        )
    }

    func makeUIView(context: Context) -> HIDIOUIKitKeyboardTextField {
        let textField = HIDIOUIKitKeyboardTextField(compositingText: $compositingText)
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
        @Binding var compositingText: String
        
        let onInsertText: (String) -> Void
        let onDeleteBackward: () -> Void
        let onReturnKey: () -> Void

        init(
            isFirstResponder: Binding<Bool>,
            compositingText: Binding<String>,
            onInsertText: @escaping (String) -> Void,
            onDeleteBackward: @escaping () -> Void,
            onReturnKey: @escaping () -> Void
        ) {
            _isFirstResponder = isFirstResponder
            _compositingText = compositingText
            
            self.onInsertText = onInsertText
            self.onDeleteBackward = onDeleteBackward
            self.onReturnKey = onReturnKey
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
            }
            
            compositingText = ""
            textField.text = ""

            if isFirstResponder {
                DispatchQueue.main.async {
                    self.isFirstResponder = false
                }
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onReturnKey()
            return false
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            // IME 조합 중에는 시스템이 텍스트를 관리하도록 허용
            // 삭제는 HIDIOUIKitKeyboardTextField.deleteBackward()에서 처리
            return true
        }

        /// IME 조합 완료 후 텍스트 필드에 남아있는 확정 텍스트를 추출하여 전송
        @objc func textFieldEditingChanged(_ textField: UITextField) {
            if textField.markedTextRange != nil || textField.textInputMode?.isKoreanInput == true {
                compositingText = textField.text ?? ""
                
                if compositingText.hasSuffix(" ") {
                    onInsertText(compositingText.trimmingCharacters(in: .newlines))
                    compositingText = ""
                    textField.text = ""
                }
                
                return
            } else {
                guard let text = textField.text, !text.isEmpty else {
                    return
                }
                
                // 확정된 텍스트를 직접 처리 (ASCII → keycodes, 비-ASCII → ucs4)
                onInsertText(text)
                compositingText = ""
                textField.text = ""
            }
        }
    }
}

extension UITextInputMode {
    // CJK 계열 언어 (변환 / 컴포지션 -> 확정이 필요한 언어) 인지 판단합니다.
    var isCJK: Bool {
        guard let language = self.primaryLanguage else {
            return false
        }

        return language.hasPrefix("ja") || language.hasPrefix("ko") || language.hasPrefix("zh")
    }
    
    var isKoreanInput: Bool {
        guard let language = self.primaryLanguage else {
            return false
        }

        return language.hasPrefix("ko")
    }
}

#Preview {
    HIDIOUIKitCJKCompositionPreviewView(compositingText: "안녕하세요!")
}

#endif
