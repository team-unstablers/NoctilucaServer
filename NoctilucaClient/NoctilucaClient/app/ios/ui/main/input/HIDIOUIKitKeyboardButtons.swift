//
//  HIDIOUIKitKeyboardButtons.swift
//  NoctilucaClient
//

#if os(iOS)

import SwiftUI
import UIKit

/// 누르는 동안 keyDown, 떼면 keyUp을 전송하는 제스처 기반 키 버튼.
struct HIDIOUIKitKeyPressButton<Label: View>: View {
    let onPress: () -> Void
    let onRelease: () -> Void
    @ViewBuilder let label: () -> Label

    @GestureState private var isPressed = false

    var body: some View {
        label()
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPressed ? Color(.systemGray4) : Color(.systemGray5))
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
            .onChange(of: isPressed) { _, newValue in
                if newValue {
                    onPress()
                } else {
                    onRelease()
                }
            }
    }
}

#endif
