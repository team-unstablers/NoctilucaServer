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
    let client: NoctilucaClient?
    @ObservedObject var keyboard: HIDIOUIKitKeyboard
    @Binding var isPresented: Bool

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
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
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
        .if(client != nil) {
            $0.onReceive(client!.uiEvents) { event in
                guard case .FIXME_projectionStarted = event else {
                    return
                }

                updateConnection(isEnabled: isPresented)
            }
        }
    }

    private func updateConnection(isEnabled: Bool) {
        guard let controller = client?.hidioController else {
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

final class HIDIOUIKitKeyboardTextView: UITextView {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var hasText: Bool {
        true
    }

    override func insertText(_ text: String) {
        onInsertText?(text)
    }

    override func deleteBackward() {
        onDeleteBackward?()
    }
}

struct HIDIOUIKitKeyboardInputView: UIViewRepresentable {
    @Binding var isFirstResponder: Bool
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isFirstResponder: $isFirstResponder)
    }

    func makeUIView(context: Context) -> HIDIOUIKitKeyboardTextView {
        let textView = HIDIOUIKitKeyboardTextView()
        textView.onInsertText = onInsertText
        textView.onDeleteBackward = onDeleteBackward
        textView.delegate = context.coordinator

        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardType = .asciiCapable
        textView.returnKeyType = .default
        textView.enablesReturnKeyAutomatically = false
        textView.isEditable = true
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textColor = .clear
        textView.tintColor = .clear
        textView.text = ""
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        return textView
    }

    func updateUIView(_ uiView: HIDIOUIKitKeyboardTextView, context: Context) {
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

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var isFirstResponder: Bool

        init(isFirstResponder: Binding<Bool>) {
            _isFirstResponder = isFirstResponder
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFirstResponder {
                DispatchQueue.main.async {
                    self.isFirstResponder = true
                }
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFirstResponder {
                DispatchQueue.main.async {
                    self.isFirstResponder = false
                }
            }
        }
    }
}

#endif
