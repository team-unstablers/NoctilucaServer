//
//  CursorEventSubscription.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation
import AsyncAlgorithms

import SiriusKit

class CursorEventSubscription {
    private let logger = NoctilucaLogger(category: "CursorEventSubscription")
    let id: UUID = UUID()

    private let cursorStateHolder = CursorStateHolder.shared
    private var stateTask: Task<Void, Never>?
    private var hashTask: Task<Void, Never>?

    weak var channel: ProjectionChannel? = nil

    init() {
    }

    deinit {
        self.stateTask?.cancel()
        self.hashTask?.cancel()
    }

    @MainActor
    func setup() {
        // cursorState 소비 - AsyncAlgorithms throttle 적용 (60Hz = ~16.67ms)
        self.stateTask = Task { [weak self] in
            guard let self = self else { return }

            let throttled = self.cursorStateHolder.makeCursorStateStream()
                ._throttle(for: .milliseconds(1000 / 60), latest: true)

            for await state in throttled {
                guard let channel = self.channel else { continue }
                try? await channel.sendCursorPositionEvent(state)
            }
        }

        // cursorHash 소비 (throttle 없음)
        self.hashTask = Task { [weak self] in
            guard let self = self else { return }

            for await _ in self.cursorStateHolder.makeCursorHashStream() {
                guard let channel = self.channel else { continue }
                do {
                    try await channel.sendCursorImageEvent()
                } catch {
                    self.logger.error("Failed to send cursor image update: \(error)")
                }
            }
        }
        
        Task { [weak self] in
            guard let self else { return }
            try? await self.channel?.sendCursorImageEvent()

            if let state = self.cursorStateHolder.cursorState {
                try? await self.channel?.sendCursorPositionEvent(state)
            }
        }
    }

    func destroy() {
        self.stateTask?.cancel()
        self.stateTask = nil
        self.hashTask?.cancel()
        self.hashTask = nil
    }
}
