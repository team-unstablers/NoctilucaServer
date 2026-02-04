//
//  ConcurrentDictionaryTests.swift
//  SiriusKitTests
//
//  Created by Codex on 2/4/26.
//

import Foundation
import Testing

@testable import SiriusKit

@Suite("ConcurrentDictionary")
struct ConcurrentDictionaryTests {
    @Test("basic operations")
    func basicOperations() {
        let dictionary = ConcurrentDictionary<String, Int>()
        
        #expect(dictionary.isEmpty)
        #expect(dictionary.count == 0)
        #expect(dictionary["missing"] == nil)
        
        dictionary["alpha"] = 1
        #expect(dictionary.count == 1)
        #expect(dictionary.contains(key: "alpha"))
        #expect(dictionary.value(forKey: "alpha") == 1)
        
        let previous = dictionary.updateValue(2, forKey: "alpha")
        #expect(previous == 1)
        #expect(dictionary["alpha"] == 2)
        
        let removed = dictionary.removeValue(forKey: "alpha")
        #expect(removed == 2)
        #expect(dictionary.isEmpty)
    }
    
    @Test("collection iteration")
    func collectionIteration() {
        let dictionary = ConcurrentDictionary<Int, String>([1: "one", 2: "two", 3: "three"])
        
        let elements = Array(dictionary)
        let keys = Set(elements.map { $0.key })
        let values = Set(elements.map { $0.value })
        
        #expect(keys == [1, 2, 3])
        #expect(values == ["one", "two", "three"])
    }
    
    @Test("mutable collection assignment")
    func mutableCollectionAssignment() {
        let dictionary = ConcurrentDictionary<String, Int>(["alpha": 1])
        
        guard let index = dictionary.firstIndex(where: { $0.key == "alpha" }) else {
            #expect(Bool(false), "expected index for existing key")
            return
        }
        
        dictionary[index] = (key: "alpha", value: 42)
        #expect(dictionary["alpha"] == 42)
    }
    
    @Test("concurrent writes")
    func concurrentWrites() {
        let dictionary = ConcurrentDictionary<Int, Int>()
        let iterations = 1000
        
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            dictionary[index] = index
        }
        
        #expect(dictionary.count == iterations)
        #expect(dictionary[0] == 0)
        #expect(dictionary[iterations - 1] == iterations - 1)
    }
}
