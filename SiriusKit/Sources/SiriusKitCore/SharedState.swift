//
//  SharedState.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 3/4/26.
//

import os
import Foundation

public class SharedState<Struct> {
    private var lock = os_unfair_lock()
    private var value: Struct
    
    public init(_ initialValue: Struct) {
        self.value = initialValue
    }
    
    func withLock<T>(_ body: (Struct) -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body(value)
    }
    
    public func mutate(_ body: (Struct) -> Struct) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = body(value)
    }
}

public extension SharedState {
    func checkpoint() -> Struct {
        withLock { $0 }
    }
}
