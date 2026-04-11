//
//  HIDIOKeystrokeHook.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

import Foundation
import SiriusKitClient

struct HIDIOKeystrokeHookIdentifier: RawRepresentable, Hashable, Equatable, Sendable {
    typealias RawValue = String
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// HIDIO를 통해 특정한 키스트로크 입력이 일어났을때, 특정한 액션을 수행할 수 있도록 합니다.
///
/// # NOTE
/// - 이 클래스는 identifier로 해시 및 동등성 비교를 수행합니다. 이는 같은 키스트로크 훅이 여러번 등록되는 것을 방지하기 위함입니다.
final class HIDIOKeystrokeHook: Sendable {
    typealias ActionFn = @Sendable () -> Void

    let condition: KeySequence
    let action: ActionFn

    init(condition: KeySequence, action: @escaping ActionFn) {
        self.condition = condition
        self.action = action
    }

    @MainActor
    func evaluate(_ state: HIDIOController.KeyPressState) -> Bool {
        let pressedKeys = state.pressedKeys

        // modifier가 모두 눌려있는지 확인
        for modifier in condition.modifier {
            if !pressedKeys.contains(modifier) {
                return false
            }
        }

        // key가 눌려있는지 확인
        if !pressedKeys.contains(condition.key) {
            return false
        }

        return true
    }
}
