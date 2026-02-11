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
        // MainActor에서 스트림과 초기값을 캡처한 뒤, detached Task로 이벤트 루프 실행
        let cursorStateStream = self.cursorStateHolder.makeCursorStateStream()
        let cursorHashStream = self.cursorStateHolder.makeCursorHashStream()
        let initialCursorState = self.cursorStateHolder.cursorState

        // cursorState 소비 - AsyncAlgorithms throttle 적용 (60Hz = ~16.67ms)
        self.stateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let throttled = cursorStateStream
                // ._throttle(for: .milliseconds(1000 / 60), latest: true)

            for await state in throttled {
                guard let channel = self?.channel else { continue }
                try? await channel.sendCursorPositionEvent(state)
            }
        }

        // cursorHash 소비 (throttle 없음)
        self.hashTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await _ in cursorHashStream {
                guard let channel = self?.channel else { continue }
                do {
                    try await channel.sendCursorImageEvent()
                } catch {
                    self?.logger.error("Failed to send cursor image update: \(error)")
                }
            }
        }

        Task.detached { [weak self] in
            try? await self?.channel?.sendCursorImageEvent()

            if let initialCursorState {
                try? await self?.channel?.sendCursorPositionEvent(initialCursorState)
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
