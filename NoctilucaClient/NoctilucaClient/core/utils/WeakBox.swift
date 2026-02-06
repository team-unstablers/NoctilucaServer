//
//  WeakBox.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

class Weak<T: AnyObject> {
    private(set) weak var _ref: T?
    
    var ref: T {
        _ref!
    }
    
    init(_ ref: T) {
        self._ref = ref
    }
}
