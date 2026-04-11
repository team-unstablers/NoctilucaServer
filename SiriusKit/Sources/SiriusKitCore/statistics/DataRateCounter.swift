//
//  DataRateCounter.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 4/3/26.
//

import Foundation

/// 슬라이딩 윈도우 기반 데이터 전송률 카운터.
///
/// `record(_:)`로 전송/수신된 바이트를 기록하고,
/// `bytesPerSecond`로 최근 윈도우 기간 내의 평균 전송률(bytes/sec)을 조회합니다.
public final class DataRateCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [(timestamp: ContinuousClock.Instant, bytes: Int)] = []
    private let windowDuration: Duration

    public init(windowDuration: Duration = .seconds(3)) {
        self.windowDuration = windowDuration
    }

    /// 전송/수신된 바이트를 기록합니다.
    public func record(_ byteCount: Int) {
        let now = ContinuousClock.now
        lock.withLock {
            samples.append((timestamp: now, bytes: byteCount))
            purge(now: now)
        }
    }

    /// 최근 윈도우 기간 내의 평균 전송률(bytes/sec)을 반환합니다.
    public var bytesPerSecond: Double {
        let now = ContinuousClock.now
        return lock.withLock {
            purge(now: now)

            guard let oldest = samples.first else {
                return 0.0
            }

            let totalBytes = samples.reduce(0) { $0 + $1.bytes }

            let elapsed = oldest.timestamp.duration(to: now)
            let elapsedSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) * 1e-18

            if elapsedSeconds < 0.001 {
                return Double(totalBytes)
            }

            return Double(totalBytes) / elapsedSeconds
        }
    }

    /// 카운터를 초기화합니다.
    public func reset() {
        lock.withLock {
            samples.removeAll()
        }
    }

    /// 윈도우 밖의 오래된 샘플을 제거합니다. lock 내부에서만 호출하세요.
    private func purge(now: ContinuousClock.Instant) {
        let cutoff = now - windowDuration
        if let firstValidIndex = samples.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValidIndex > 0 {
                samples.removeFirst(firstValidIndex)
            }
        } else {
            samples.removeAll()
        }
    }
}
