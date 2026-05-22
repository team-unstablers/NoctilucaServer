//
//  SimpleRPCChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/22/26.
//

import SiriusKit

import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

final class SimpleRPCChannel: Channel, ChannelEventConsumer {
    private let logger = NoctilucaLogger(category: "SimpleRPCChannel")
    
    let handle: ChannelHandle
    
    init(handle: ChannelHandle) {
        self.handle = handle
    }
    
    // MARK: - ChannelEventConsumer
    
    func handleChannelReady() async {
        await handle.setServiceClass(.default)
    }
    
    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        // guard frame.opcode == .

    }

    func handleError(error: any Error) async {
        logger.error("channel error: \(error)")
    }

    func handleStreamClose() async {
    }
}
