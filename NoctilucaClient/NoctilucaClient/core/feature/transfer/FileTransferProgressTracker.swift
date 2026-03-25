//
//  FileTransferProgressTracker.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/25/26.
//

import Foundation
import Combine

/// 활성 TransferChannel들의 진행률을 집계하여 UI에 노출하는 트래커.
/// 모든 메서드는 @MainActor에서 호출되어야 한다.
@MainActor
class FileTransferProgressTracker: ObservableObject {
    struct Entry {
        let totalSize: UInt64
        var transferredBytes: UInt64
    }

    /// 집계된 진행률. 활성 전송이 없으면 nil.
    @Published private(set) var aggregatedProgress: Double? = nil

    private var entries: [UUID: Entry] = [:]

    /// 새 전송을 등록한다.
    func register(channelID: UUID, totalSize: UInt64) {
        entries[channelID] = Entry(totalSize: totalSize, transferredBytes: 0)
        recalculate()
    }

    /// 전송된 바이트 수를 누적한다.
    func update(channelID: UUID, additionalBytes: UInt64) {
        guard entries[channelID] != nil else { return }
        entries[channelID]!.transferredBytes += additionalBytes
        recalculate()
    }

    /// 전송 완료 또는 채널 종료 시 제거한다.
    func unregister(channelID: UUID) {
        entries.removeValue(forKey: channelID)
        recalculate()
    }

    /// 모든 항목을 제거한다.
    func reset() {
        entries.removeAll()
        aggregatedProgress = nil
    }

    private func recalculate() {
        guard !entries.isEmpty else {
            aggregatedProgress = nil
            return
        }

        let totalExpected = entries.values.reduce(UInt64(0)) { $0 + $1.totalSize }
        let totalTransferred = entries.values.reduce(UInt64(0)) { $0 + $1.transferredBytes }

        guard totalExpected > 0 else {
            aggregatedProgress = 0.0
            return
        }

        aggregatedProgress = min(Double(totalTransferred) / Double(totalExpected), 1.0)
    }
}
