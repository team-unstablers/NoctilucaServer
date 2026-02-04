//
//  ConcurrentDictionary.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/4/26.
//

import Foundation
import os

// @codex, Dictionary-like protocol이 있어? 만약 그렇다면 이걸 만족할 수 있도록 하고 싶어

@available(iOS 16.0, macOS 13.0, *)
public final class ConcurrentDictionary<Key: Hashable, Value> {
    private var dictionary: [Key: Value] = [:]
    private let lock = OSAllocatedUnfairLock()
    
    public init() {}
    
    public init(_ dictionary: [Key: Value]) {
        self.dictionary = dictionary
    }

    public subscript(key: Key) -> Value? {
        get {
            lock.withLock { dictionary[key] }
        }
        set {
            lock.withLock { dictionary[key] = newValue }
        }
    }
    
    public var count: Int {
        lock.withLock { dictionary.count }
    }
    
    public var isEmpty: Bool {
        lock.withLock { dictionary.isEmpty }
    }
    
    public var keys: [Key] {
        lock.withLock { Array(dictionary.keys) }
    }
    
    public var values: [Value] {
        lock.withLock { Array(dictionary.values) }
    }
    
    public func contains(key: Key) -> Bool {
        lock.withLock { dictionary[key] != nil }
    }
    
    public func value(forKey key: Key) -> Value? {
        lock.withLock { dictionary[key] }
    }
    
    @discardableResult
    public func updateValue(_ value: Value, forKey key: Key) -> Value? {
        lock.withLock { dictionary.updateValue(value, forKey: key) }
    }
    
    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        lock.withLock { dictionary.removeValue(forKey: key) }
    }
    
    public func removeAll(keepingCapacity: Bool = false) {
        lock.withLock { dictionary.removeAll(keepingCapacity: keepingCapacity) }
    }
    
    public func reserveCapacity(_ minimumCapacity: Int) {
        lock.withLock { dictionary.reserveCapacity(minimumCapacity) }
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension ConcurrentDictionary: Collection, MutableCollection {
    public typealias Element = (key: Key, value: Value)
    public typealias Index = Dictionary<Key, Value>.Index
    
    /// Note: Dictionary indices are invalidated by mutations.
    /// Avoid holding indices across concurrent writes.
    public var startIndex: Index {
        lock.withLock { dictionary.startIndex }
    }
    
    public var endIndex: Index {
        lock.withLock { dictionary.endIndex }
    }
    
    public func index(after i: Index) -> Index {
        lock.withLock { dictionary.index(after: i) }
    }
    
    public subscript(position: Index) -> Element {
        get {
            lock.withLock { dictionary[position] }
        }
        set {
            lock.withLock {
                let currentKey = dictionary[position].key
                precondition(currentKey == newValue.key, "ConcurrentDictionary: key mismatch on indexed assignment")
                dictionary[currentKey] = newValue.value
            }
        }
    }
    
    public func makeIterator() -> Dictionary<Key, Value>.Iterator {
        lock.withLock { dictionary }.makeIterator()
    }
}
