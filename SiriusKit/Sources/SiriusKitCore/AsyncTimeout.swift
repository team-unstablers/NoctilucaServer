//
//  AsyncTimeout.swift
//  SiriusKit
//

import Foundation
import os

/// `withTimeout(...)` 가 deadline 안에 완료되지 못한 경우 throw 됩니다.
public struct AsyncTimeoutError: Error, Sendable {
    public init() {}
}

/// 비동기 작업을 주어진 시간 내에 완료하도록 강제합니다.
///
/// - 작업이 시간 안에 완료되면 결과를 그대로 반환합니다.
/// - 시간이 초과되면 ``AsyncTimeoutError`` 가 throw 되며, 내부 작업 Task 는
///   `cancel()` 호출 후 백그라운드에서 자연 종료됩니다.
/// - 작업이 cancellation 에 반응하지 않더라도 호출자는 deadline 시점에 풀려납니다.
///
/// - Parameters:
///   - seconds: deadline (초). 이 시간이 지나면 ``AsyncTimeoutError`` 가 throw 됩니다.
///   - operation: 실행할 비동기 작업.
/// - Throws: deadline 초과 시 ``AsyncTimeoutError``, 또는 `operation` 이 던진 에러.
@discardableResult
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    let resumed = OSAllocatedUnfairLock(initialState: false)

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let workTask = Task {
            do {
                let result = try await operation()
                let shouldResume = resumed.withLock { state -> Bool in
                    if state { return false }
                    state = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: result)
                }
            } catch {
                let shouldResume = resumed.withLock { state -> Bool in
                    if state { return false }
                    state = true
                    return true
                }
                if shouldResume {
                    continuation.resume(throwing: error)
                }
            }
        }

        Task {
            let nanoseconds = UInt64((seconds * 1_000_000_000.0).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
            let shouldResume = resumed.withLock { state -> Bool in
                if state { return false }
                state = true
                return true
            }
            if shouldResume {
                workTask.cancel()
                continuation.resume(throwing: AsyncTimeoutError())
            }
        }
    }
}

