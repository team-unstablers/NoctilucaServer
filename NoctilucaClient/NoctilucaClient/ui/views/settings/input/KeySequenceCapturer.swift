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

struct KeySequence: Hashable, Equatable {
    let modifier: Set<LinuxKeycode>
    let key: LinuxKeycode
    
    init(modifier: Set<LinuxKeycode>, key: LinuxKeycode) {
        self.modifier = modifier
        self.key = key
    }
    
    func addModifier(_ modifier: LinuxKeycode) -> Self {
        return KeySequence(modifier: self.modifier.union([modifier]), key: self.key)
    }
    
    func setKey(_ key: LinuxKeycode) -> Self {
        return KeySequence(modifier: self.modifier, key: key)
    }
}

extension KeySequence {
    static let empty = KeySequence(modifier: [], key: .KEY_UNKNOWN)
}

extension KeySequence: CustomStringConvertible {
    fileprivate var modifierDescription: String {
        // 정렬 순서: Control, Option, Shift, Command
        
        guard !modifier.isEmpty else {
            return ""
        }
        
        var description: String = ""
        
        if modifier.contains(.KEY_LEFTCTRL) {
            description.append(LinuxKeycode.KEY_LEFTCTRL.appleSymbol!)
        }
        
        if modifier.contains(.KEY_LEFTALT) {
            description.append(LinuxKeycode.KEY_LEFTALT.appleSymbol!)
        }
        
        if modifier.contains(.KEY_LEFTSHIFT) {
            description.append(LinuxKeycode.KEY_LEFTSHIFT.appleSymbol!)
        }
        
        if modifier.contains(.KEY_LEFTMETA) {
            description.append(LinuxKeycode.KEY_LEFTMETA.appleSymbol!)
        }
        
        return description
    }
    
    var description: String {
        guard self != .empty else {
            return "(없음)"
        }
        
        if key == .KEY_UNKNOWN {
            return modifierDescription
        }
        
        return (modifierDescription + (key.appleSymbol ?? key.appleDescription ?? key.description))
    }
}

struct KeySequenceLabel: View {
    let keySequence: KeySequence
    
    var body: some View {
        Text(keySequence.description)
    }
}

struct KeySequenceCapturer<Label: View>: View {
    @Binding
    var keySequence: KeySequence
    
    @ViewBuilder
    let label: () -> Label
    
    @State
    private var isCapturing: Bool = false
    
    init(keySequence: Binding<KeySequence>, @ViewBuilder label: @escaping () -> Label) {
        // HACK: HIDIOGCKeyboard.shared()를 호출해서 GCKeyboard.coalesced가 nil이 아님을 보장해야 한다
        _ = HIDIOGCKeyboard.shared()
        
        self._keySequence = keySequence
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
            
            if keySequence.key == .KEY_UNKNOWN || keySequence.key == .KEY_ESC {
                // modifier 키만 눌린 상태로 타임아웃된 경우는 무시
                self.keySequence = .empty
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
                    // TODO: left / right를 sanitize 한다: 무조건 left로 바꾸기
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
