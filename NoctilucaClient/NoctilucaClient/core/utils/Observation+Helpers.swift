//
//  Observation+Helpers.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation
import Observation

/// `@Observable` 객체의 프로퍼티 변경을 콜백 기반으로 관찰하는 헬퍼.
///
/// `withObservationTracking`의 `onChange`는 1회만 호출되므로, 변경이 감지될 때마다
/// 재귀적으로 재구독하여 Combine `sink`와 유사한 지속 관찰 생명주기를 제공한다.
/// 구독 수명은 `apply`가 캡처한 객체의 생존 기간을 따른다 — `[weak self]` 등
/// 약한 참조로 캡처하고, 클로저 내부에서 self가 nil이면 조기 반환하여 루프를 끊는다.
///
/// `NSObject.observe(_:options:changeHandler:)` (KVO) 과의 이름 충돌을 피하기 위해
/// `observeChanges`로 명명한다.
///
/// - Parameter apply: 관찰 시 실행할 클로저. 내부에서 읽은 `@Observable` 프로퍼티가
///   추적 대상이 된다. 변경이 감지되면 main actor 컨텍스트에서 다시 호출된다.
@MainActor
func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in
            observeChanges(apply)
        }
    }
}
