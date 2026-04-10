//
//  CursorEventSubscription.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation

import SiriusKit

@MainActor
final class CursorEventSubscription {
    private let logger = NoctilucaLogger(category: "CursorEventSubscription")

    nonisolated let id: UUID = UUID()

    private let cursorStateHolder = CursorStateHolder.shared
    private var stateTask: Task<Void, Never>?
    private var hashTask: Task<Void, Never>?

    weak var channel: ProjectionChannel? = nil

    init() {}

    deinit {
        // nonisolated context. Task<Void, Never>?.cancel() 은 thread-safe.
        stateTask?.cancel()
        hashTask?.cancel()
    }

    func setChannel(_ channel: ProjectionChannel?) {
        self.channel = channel
    }

    func setup() async {
        // MainActor에서 스트림과 초기값을 캡처한 뒤, detached Task로 이벤트 루프 실행
        let cursorStateStream  = await self.cursorStateHolder.makeCursorStateStream()
        let cursorHashStream   = await self.cursorStateHolder.makeCursorHashStream()
        let initialCursorState = await self.cursorStateHolder.cursorState

        // cursorState 소비: 커서 위치 이벤트를 120Hz로 제한하여 메인/네트워크 큐 적체를 완화한다.
        self.stateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let minSendIntervalNanos: UInt64 = 8_333_333 // ~120Hz
            var lastSentState: CursorState?
            var lastSentAtNanos: UInt64 = 0

            for await state in cursorStateStream {
                guard let channel = await self?.channel else { continue }

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
                    await self?.logError("Failed to send cursor position update: \(error)")
                }
            }
        }

        // cursorHash 소비 (throttle 없음)
        self.hashTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await _ in cursorHashStream {
                guard let channel = await self?.channel else { continue }
                do {
                    try await channel.sendCursorImageEvent()
                } catch {
                    await self?.logError("Failed to send cursor image update: \(error)")
                }
            }
        }

        let initialChannel = self.channel
        Task.detached {
            try? await initialChannel?.sendCursorImageEvent()

            if let initialCursorState {
                try? await initialChannel?.sendCursorPositionEvent(initialCursorState)
            }
        }
    }

    nonisolated func destroy() {
        Task { @MainActor [weak self] in
            self?.stateTask?.cancel()
            self?.stateTask = nil
            self?.hashTask?.cancel()
            self?.hashTask = nil
        }
    }

    private func logError(_ message: String) {
        logger.error("\(message)")
    }
}
