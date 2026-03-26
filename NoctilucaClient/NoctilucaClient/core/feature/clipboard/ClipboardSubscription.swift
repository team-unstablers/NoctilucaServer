//
//  ClipboardSubscription.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//
import Foundation

import SiriusKitClient

class ClipboardSubscription: Identifiable {
    let id: UUID

    private let logger = NoctilucaLogger(category: "ClipboardSubscription")

    weak var channel: ClipboardChannel?

    /// 세션 설정에서 주입된 클립보드 설정
    var clipboardSettings: SessionSettings.Clipboard = .init()

    init() {
        self.id = UUID()
    }

    deinit {
        let id = self.id
        Task { @MainActor in
            ClipboardWatcher.shared.removeSubscriberById(id)
        }
    }

    @MainActor
    func setup() {
        ClipboardWatcher.shared.addSubscriber(self)
    }

    @MainActor
    func destroy() {
        ClipboardWatcher.shared.removeSubscriber(self)
    }

    /// ClipboardWatcher로부터 변경 알림을 받았을 때 호출됩니다.
    @MainActor
    func notifyChange() {
        guard let channel = channel else { return }

        // useBidirectionalSync가 false면 클라이언트→서버 발신 차단 (서버→클라이언트 수신만 허용)
        guard clipboardSettings.useBidirectionalSync else {
            return
        }

        let snapshot = ClipboardManager.shared.currentWithSnapshot(settings: clipboardSettings)
        guard !snapshot.items.isEmpty else { return }

        let event = ClipboardEvent(
            subscriptionId: self.id,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            items: snapshot.items
        )

        Task {
            do {
                channel.storeSnapshot(snapshot.omittedData)
                channel.storeFileTransferSnapshot(snapshot.fileTransferData)
                try await channel.send(opcode: .clipboardEvent, message: event)
            } catch {
                logger.error("Failed to send ClipboardEvent: \(error)")
            }
        }
    }
}
