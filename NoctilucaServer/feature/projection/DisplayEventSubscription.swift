//
//  DisplayEventSubscription.swift
//  NoctilucaServer
//
//  Created by Claude on 1/28/26.
//

import Foundation
import Combine

import SiriusKit

class DisplayEventSubscription {
    let id: UUID = UUID()

    private let displayLayoutManager = DisplayLayoutManager.shared
    private var subscription: AnyCancellable? = nil

    /// 구독할 이벤트 마스크 (0이면 모든 이벤트 구독)
    let eventMask: DisplayChangeEventType

    weak var channel: ProjectionChannel? = nil

    init(eventMask: DisplayChangeEventType) {
        self.eventMask = eventMask
    }

    deinit {
        self.subscription?.cancel()
    }

    @MainActor
    func setup() {
        // displayChangePublisher는 이미 1초 디바운스가 적용되어 있음
        let subscription = displayLayoutManager.displayChangePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
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

                Task {
                    try? await channel.sendDisplayChangedEvent(event)
                }
            }

        self.subscription = subscription
    }

    func destroy() {
        self.subscription?.cancel()
        self.subscription = nil
    }
}
