//
//  JSPromise.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 8/27/24.
//  Updated by Google Gemini (gemini-3-pro) on 3/23/26.
//

import Foundation
internal import Atomics

// Swift 6+를 위해 @Sendable 적용
public typealias JSPromiseResolveBlock<T> = @Sendable (T) -> Void
public typealias JSPromiseRejectBlock = @Sendable (Error) -> Void
public typealias JSPromiseCodeBlock<T> = @Sendable (@escaping JSPromiseResolveBlock<T>, @escaping JSPromiseRejectBlock) throws -> Void

fileprivate let logger = SiriusLogger(category: "JSPromise")

/**
 Provides a true JavaScript-style promise (Eager execution & Result caching).
 */
public struct JSPromise<T: Sendable>: Sendable {
    // Task 자체를 래핑하여 결과 캐싱과 즉시 실행을 보장합니다.
    private let task: Task<T, Error>
    
    public init(_ block: @escaping JSPromiseCodeBlock<T>) {
        // JS Promise처럼 생성과 동시에 백그라운드에서 즉시 실행됩니다.
        self.task = Task {
            try await withCheckedThrowingContinuation { continuation in
                // 상태를 Task 내부에 두어 여러 번 await 해도 안전합니다.
                let isResumed = ManagedAtomic<Bool>(false)
                
                // 중복 코드를 제거하고 깔끔하게 Result 단위로 처리하는 헬퍼 함수
                let complete: @Sendable (Result<T, Error>) -> Void = { result in
                    if isResumed.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).exchanged {
                        continuation.resume(with: result)
                    } else {
                        logger.error("resolve() / reject() called more than once!")
                    }
                }
                
                let resolve: JSPromiseResolveBlock<T> = { value in complete(.success(value)) }
                let reject: JSPromiseRejectBlock = { error in complete(.failure(error)) }
                
                do {
                    try block(resolve, reject)
                } catch {
                    reject(error) // 동기적 에러 발생 시 안전하게 reject로 라우팅
                }
            }
        }
    }
    
    public func callAsFunction() async throws -> T {
        // 여러 번 호출해도 내부 Task가 캐싱한 동일한 결과를 즉시 반환합니다.
        return try await task.value
    }
}
