//
//  FrameQueue.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/8/26.
//

import Foundation

import SiriusKit


actor FrameQueue<Frame: Sendable> {
    private let logger = NoctilucaLogger(category: "FrameQueue")
    
    private var capacity: Int
    private var queue: [Frame] = []
    
    // deinit에서 접근하기 위해 nonisolated로 선언.
    nonisolated(unsafe) private var waiter: CheckedContinuation<Frame, any Error>? = nil
    
    init(capacity: Int) {
        self.capacity = capacity

        self.logger.debug("Initialized with capacity: \(capacity)")
    }

    deinit {
        if let waiter = self.waiter {
            self.waiter = nil
            waiter.resume(throwing: CancellationError())
        }
    }
    
    func setCapacity(_ capacity: Int) {
        self.logger.info("Setting capacity from \(self.capacity) to \(capacity)")
        self.capacity = capacity
    }
    
    @discardableResult
    func enqueue(_ frame: consuming Frame) -> Bool {
        // waiter가 있으면 큐를 거치지 않고 직접 resume
        if let waiter = self.waiter {
            self.waiter = nil
            waiter.resume(returning: frame)
            return false
        }

        var dropped = false
        if queue.count >= capacity {
            // logger.trace("FrameQueue is full. Dropping the oldest frame.")
            queue.removeFirst()
            dropped = true
        }

        queue.append(frame)
        return dropped
    }

    var count: Int { queue.count }

    /// 큐 용량 대비 현재 프레임 수 비율 (0.0 ~ 1.0)
    var pressure: Float { Float(queue.count) / Float(max(capacity, 1)) }
    
    func clear() {
        logger.info("Clearing FrameQueue with \(self.queue.count) frames.")
        
        queue.removeAll()
    }

    func cancelWaiter() {
        guard let waiter = self.waiter else {
            return
        }

        self.waiter = nil
        waiter.resume(throwing: CancellationError())
    }
    
    func isEmpty() -> Bool {
        return queue.isEmpty
    }

    func next() async throws -> Frame {
        if !queue.isEmpty {
            let frame = queue.removeFirst()
            
            return frame
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // There should be only one waiter at a time
            assert(self.waiter == nil, "There is already a waiter waiting for the next frame.")
            self.waiter = continuation
        }
    }
    
}
