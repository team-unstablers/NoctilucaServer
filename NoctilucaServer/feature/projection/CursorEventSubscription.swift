//
//  CursorEventSubscription.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation

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

        // cursorState 소비: 커서 위치 이벤트를 120Hz로 제한하여 메인/네트워크 큐 적체를 완화한다.
        self.stateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let minSendIntervalNanos: UInt64 = 8_333_333 // ~120Hz
            var lastSentState: CursorState?
            var lastSentAtNanos: UInt64 = 0

            for await state in cursorStateStream {
                guard let channel = self?.channel else { continue }

                if lastSentState == state {
                    continue
                }

                let now = DispatchTime.now().uptimeNanoseconds
                if lastSentAtNanos != 0, (now - lastSentAtNanos) < minSendIntervalNanos {
                    continue
                }

                do {
                    try await channel.sendCursorPositionEvent(state)
                    lastSentState = state
                    lastSentAtNanos = DispatchTime.now().uptimeNanoseconds
                } catch {
                    self?.logger.error("Failed to send cursor position update: \(error)")
                }
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
