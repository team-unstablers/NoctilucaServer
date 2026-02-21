//
//  HIDIOUIKitKeyboardView.swift
//  NoctilucaClient
//
//  Created by Codex on 12/31/25.
//

#if os(iOS)

import SwiftUI

import SiriusKitClient

struct HIDIOUIKitCJKCompositionPreviewView: View {
    let compositingText: String

    var body: some View {
        VStack(spacing: 0) {
            Text(compositingText)
                .font(.system(size: 18))
                .padding(4)
            HStack {
                Text(markdown: String(localized: "main.input.keyboard.cjk_hint", defaultValue: "스페이스 바 / ↩︎ 키로 확정 — CJK Composition Preview"))
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
                keyboard: keyboard,
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

#Preview {
    HIDIOUIKitCJKCompositionPreviewView(compositingText: "안녕하세요!")
}

#endif
