//
//  MockChannel.swift
//  SiriusKitTests
//
//  Channel 프로토콜의 최소 구현체로, MockFeatureProvider가 `.accepted(...)`로 반환할
//  기본 채널 타입이다. handle 보유 외의 로직은 없다.
//

import Foundation
@testable import SiriusKitCore

final class MockChannel: Channel {
    let handle: ChannelHandle

    init(handle: ChannelHandle) {
        self.handle = handle
    }
}
