//
//  KeySequenceCapturer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/27/25.
//

import Foundation

import SwiftUI

import GameController

import SiriusKitClient

// TODO: 이거 fileprivate 떼거나 해야 함
fileprivate extension LinuxKeycode {
    var sanitizedLeftVariant: LinuxKeycode {
        switch self {
        case .KEY_RIGHTCTRL:
            return .KEY_LEFTCTRL
        case .KEY_RIGHTSHIFT:
            return .KEY_LEFTSHIFT
        case .KEY_RIGHTALT:
            return .KEY_LEFTALT
        case .KEY_RIGHTMETA:
            return .KEY_LEFTMETA
        default:
            return self
        }
    }
}

struct KeySequenceLabel: View {
    let keySequence: KeySequence
    
    var body: some View {
        Text(keySequence.description)
    }
}

struct KeySequenceCapturerPolicy: OptionSet, Sendable {
    let rawValue: Int
    
    static let none = Self([])
    static let `default` = Self([.disallowEscapeKey])
    
    /// Escape 키의 캡쳐를 허용하지 않습니다.
    static let disallowEscapeKey = Self(rawValue: 1 << 0)
}

struct KeySequenceCapturer<Label: View>: View {
    @Binding
    var keySequence: KeySequence
    
    let policy: KeySequenceCapturerPolicy
    let `default`: KeySequence

    @ViewBuilder
    let label: () -> Label
    
    
    @State
    private var isCapturing: Bool = false
    
    init(keySequence: Binding<KeySequence>,
         policy: KeySequenceCapturerPolicy = .default,
         `default`: KeySequence = .empty,
         @ViewBuilder label: @escaping () -> Label) {
        // HACK: HIDIOGCKeyboard.shared()를 호출해서 GCKeyboard.coalesced가 nil이 아님을 보장해야 한다
        _ = HIDIOGCKeyboard.shared()
        
        self._keySequence = keySequence
        self.policy = policy
        self.default = `default`
        self.label = label
    }
    
    var body: some View {
        VStack {
            Button {
                keySequence = .empty
                captureKeySequence()
            } label: {
                label()
            }
            .disabled(isCapturing)
        }
    }
    
    func captureKeySequence() {
        guard let keyboard = GCKeyboard.coalesced,
              let keyboardInput = keyboard.keyboardInput
        else {
            return
        }
        
        self.isCapturing = true
        
        var timeoutTask: Task<Void, Never>? = nil
        
        func finalize() {
            defer {
                timeoutTask?.cancel()
            }
            // 타임아웃: 키 캡처 종료
            keyboardInput.keyChangedHandler = nil
            self.isCapturing = false
            
            if keySequence.key == .KEY_UNKNOWN {
                // modifier 키만 눌린 상태로 타임아웃된 경우는 무시
                self.keySequence = self.default
            }
            
            if policy.contains(.disallowEscapeKey),
               keySequence.key == .KEY_ESC
            {
                // Escape 키 캡처는 무시
                self.keySequence = self.default
            }
        }
        
        func updateTimeout() {
            timeoutTask?.cancel()
            timeoutTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(2000))
                    
                    finalize()
                } catch {
                    // interrupted
                }
            }
        }
        
        // TODO: keyboardInput.keyChangedHandler를 덮어씌운 뒤 끝나고 원래 값으로 복원한다
        keyboardInput.keyChangedHandler = { _, key, keyCode, pressed in
            if pressed {
                let keyCode = LinuxKeycode.from(gameController: keyCode)
                
                if keyCode.isModifierKey {
                    self.keySequence = self.keySequence.addModifier(keyCode.sanitizedLeftVariant)
                } else {
                    self.keySequence = self.keySequence.setKey(keyCode)
                    finalize()
                }
                
                updateTimeout()
            }
        }
        
        updateTimeout()
    }
}

#Preview {
    @Previewable
    @State
    var keySequence: KeySequence = .empty
    
    VStack {
        KeySequenceCapturer(keySequence: $keySequence) {
            KeySequenceLabel(keySequence: keySequence)
        }
    }
    .padding(32)
    .frame(minWidth: 640)
}
