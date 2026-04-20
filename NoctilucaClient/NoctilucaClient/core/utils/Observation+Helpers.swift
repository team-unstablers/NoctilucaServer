//
//  Observation+Helpers.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation
import Observation

/// `observeChanges(_:)` 루프를 외부에서 끊을 수 있게 하는 취소 토큰.
///
/// 재귀 관찰 루프 내부에서 매 재구독 직전 `isCancelled`를 검사하여, 소유자가
/// `cancel()`을 호출하면 다음 관찰 등록을 건너뛰고 루프를 종료한다. Combine의
/// `AnyCancellable`과 동일한 역할.
@MainActor
final class ObservationHandle {
    private(set) var isCancelled: Bool = false

    init() {}

    func cancel() {
        isCancelled = true
    }
}

/// `@Observable` 객체의 프로퍼티 변경을 콜백 기반으로 관찰하는 헬퍼.
///
/// `withObservationTracking`의 `onChange`는 1회만 호출되므로, 변경이 감지될 때마다
/// 재귀적으로 재구독하여 Combine `sink`와 유사한 지속 관찰 생명주기를 제공한다.
///
/// 반환된 `ObservationHandle`의 `cancel()`을 호출하면 다음 재구독 시점에 루프가
/// 종료된다. 명시적 취소가 필요 없는 경우 반환값을 무시해도 되며, 이 경우에는
/// `apply` 클로저가 캡처한 객체 수명이 끝나면 자연 종료된다 (`[weak self]` 패턴).
///
/// `NSObject.observe(_:options:changeHandler:)` (KVO) 과의 이름 충돌을 피하기 위해
/// `observeChanges`로 명명한다.
///
/// - Parameter apply: 관찰 시 실행할 클로저. 내부에서 읽은 `@Observable` 프로퍼티가
///   추적 대상이 된다. 변경이 감지되면 main actor 컨텍스트에서 다시 호출된다.
/// - Returns: 관찰 루프를 외부에서 끊기 위한 `ObservationHandle`.
@MainActor
@discardableResult
func observeChanges(_ apply: @escaping @MainActor () -> Void) -> ObservationHandle {
    let handle = ObservationHandle()
    _scheduleObservation(apply: apply, handle: handle)
    return handle
}

/// `observeChanges`의 재귀 루프 본체. global 함수로 분리하여 onChange의
/// `@Sendable` 문맥에서 local function을 capture하지 않도록 한다.
///
/// `handle`은 **strong 캡처**다 — 호출자가 반환된 handle을 저장하지 않더라도
/// 재귀 루프가 유지되어야 하기 때문이다. 루프 종료 경로는 두 가지:
/// 1. 외부에서 명시적으로 `handle.cancel()` 호출 → 다음 재구독 시점에 종료.
/// 2. `apply` 내부가 `[weak self]` 등으로 weak 캡처 → self 해제 시 apply가 아무
///    프로퍼티도 읽지 않아 tracking set이 비게 되고, onChange가 더 이상 발화되지
///    않아 자연 종료된다.
@MainActor
private func _scheduleObservation(
    apply: @escaping @MainActor () -> Void,
    handle: ObservationHandle
) {
    guard !handle.isCancelled else { return }
    withObservationTracking {
        apply()
    } onChange: { [handle] in
        Task { @MainActor in
            guard !handle.isCancelled else { return }
            _scheduleObservation(apply: apply, handle: handle)
        }
    }
}
