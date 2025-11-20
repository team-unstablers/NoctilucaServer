//
//  Stream.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

typealias StreamIdentifier = UInt64

enum StreamError: Error {
    case notImplemented
}

protocol StreamDelegate: AnyObject {
    func streamDidReceiveData(_ stream: Stream, data: Data)
    func streamDidClose(_ stream: Stream, error: Error?)
}

class Stream {
    weak var delegate: StreamDelegate?
    
    open var id: StreamIdentifier {
        return 0
    }
    
    open func write(_ data: Data) async -> Result<UInt64, StreamError> {
        return .failure(.notImplemented)
    }
    
    open func close() async throws {
        // To be implemented by subclasses
    }
}


