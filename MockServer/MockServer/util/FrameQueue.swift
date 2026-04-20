//
//  FrameQueue.swift
//  MockServer
//
//  Copied from NoctilucaServer/feature/projection/FrameQueue.swift
//

import Foundation
import SiriusKit

actor FrameQueue<Frame: Sendable> {
    private let logger = SiriusLogger(category: "FrameQueue", subsystem: "app.noctiluca.mockserver")

    private var capacity: Int
    private var queue: [Frame] = []

    private nonisolated(unsafe) var waiter: CheckedContinuation<Frame, any Error>?

    init(capacity: Int) {
        self.capacity = capacity
    }

    deinit {
        if let waiter = self.waiter {
            self.waiter = nil
            waiter.resume(throwing: CancellationError())
        }
    }

    @discardableResult
    func enqueue(_ frame: consuming Frame) -> Bool {
        if let waiter = self.waiter {
            self.waiter = nil
            waiter.resume(returning: frame)
            return false
        }

        var dropped = false
        if queue.count >= capacity {
            queue.removeFirst()
            dropped = true
        }

        queue.append(frame)
        return dropped
    }

    var count: Int { queue.count }

    func clear() {
        queue.removeAll()
    }

    func cancelWaiter() {
        guard let waiter = self.waiter else { return }
        self.waiter = nil
        waiter.resume(throwing: CancellationError())
    }

    func next() async throws -> Frame {
        if !queue.isEmpty {
            return queue.removeFirst()
        }

        return try await withCheckedThrowingContinuation { continuation in
            assert(self.waiter == nil, "There is already a waiter waiting for the next frame.")
            self.waiter = continuation
        }
    }
}
