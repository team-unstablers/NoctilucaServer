//
//  HIDIOUIKitKeyboardInputView.swift
//  NoctilucaClient
//

#if os(iOS)

import SwiftUI
import UIKit

// MARK: - Text Field

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

// MARK: - Input View (UIViewRepresentable)

struct HIDIOUIKitKeyboardInputView: UIViewRepresentable {
    @Binding var isFirstResponder: Bool
    @Binding var compositingText: String

    let keyboard: HIDIOUIKitKeyboard
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
        textField.inputAccessoryView = HIDIOUIKitKeyboardAccessoryView(keyboard: keyboard)

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

// MARK: - UITextInputMode Extensions

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

#endif
