//
//  MainChannel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public protocol MainChannelDelegate: AnyObject {
}

public class MainChannel: Channel {
    weak var delegate: MainChannelDelegate?
    
    override func handleData(_ data: Data) {
        
    }
    
    override func handleStreamClose(error: (any Error)?) {
        
    }
}

public extension MainChannel {
    func sendNotice() {
        
    }
    
    func sendServerHello(_ payload: ServerHello) async throws {
        try await self.send(opcode: .serverHello, message: payload)
    }
    
}
