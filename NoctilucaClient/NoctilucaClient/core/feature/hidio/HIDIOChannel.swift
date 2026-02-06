//
//  HIDIO.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient


class HIDIOChannel: Channel {
    private(set) var controller: HIDIOController!

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
        
        assert(direction == .local, "HIDIOChannel must be opened from client side")
        
        self.controller = HIDIOController(channel: self)
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        // 클라이언트는 HIDIO 프레임을 수신하지 않는다
    }
}
