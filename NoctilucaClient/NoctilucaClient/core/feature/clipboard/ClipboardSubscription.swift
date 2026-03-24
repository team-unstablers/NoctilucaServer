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
    func notifyChange(snapshot: ClipboardSnapshot) {
        guard let channel = channel else { return }

        // let settings = SettingsStore.shared.settings.clipboard

        // syncDirection 체크: localToRemote 또는 bidirectional일 때만 전송
        /*
        guard settings.syncDirection == .localToRemote ||
              settings.syncDirection == .bidirectional else {
            return
        }
         */

        let event = ClipboardEvent(
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            items: snapshot.items
        )

        Task {
            do {
                channel.storeSnapshot(snapshot.omittedData)
                try await channel.send(opcode: .clipboardEvent, message: event)
            } catch {
                logger.error("Failed to send ClipboardEvent: \(error)")
            }
        }
    }
}
