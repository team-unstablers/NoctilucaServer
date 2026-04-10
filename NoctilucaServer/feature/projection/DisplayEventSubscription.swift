//
//  DisplayEventSubscription.swift
//  NoctilucaServer
//
//  Created by Claude on 1/28/26.
//

import Foundation
@preconcurrency import Combine

import SiriusKit

@MainActor
final class DisplayEventSubscription {
    nonisolated let id: UUID = UUID()

    private let displayLayoutManager = DisplayLayoutManager.shared
    private var subscription: AnyCancellable? = nil

    /// 구독할 이벤트 마스크 (0이면 모든 이벤트 구독)
    nonisolated let eventMask: DisplayChangeEventType

    weak var channel: ProjectionChannel? = nil

    init(eventMask: DisplayChangeEventType) {
        self.eventMask = eventMask
    }

    deinit {
        // nonisolated context. AnyCancellable.cancel() 은 thread-safe.
        subscription?.cancel()
    }

    func setChannel(_ channel: ProjectionChannel?) {
        self.channel = channel
    }

    func setup() {
        // displayChangePublisher는 이미 1초 디바운스가 적용되어 있음
        let subscription = displayLayoutManager.displayChangeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self = self,
                          let channel = self.channel else {
                        return
                    }

                    // eventMask가 0이면 모든 이벤트 구독
                    // 그렇지 않으면 마스크 필터링
                    let shouldSend = self.eventMask.isEmpty ||
                        !self.eventMask.intersection(event.eventType).isEmpty

                    guard shouldSend else {
                        return
                    }

                    try? await channel.sendDisplayChangedEvent(event)
                }
            }

        self.subscription = subscription
    }

    nonisolated func destroy() {
        Task { @MainActor [weak self] in
            self?.subscription?.cancel()
            self?.subscription = nil
        }
    }
}
