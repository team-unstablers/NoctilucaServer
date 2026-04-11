//
//  MainChannel+Client.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/14/25.
//

import Foundation
import SiriusKitCore

extension MainChannel {
    fileprivate static let pongFrame = SiriusFrame(opcode: .pong, length: 0, data: Data())

    /// client role에서만 사용한다
    public func sendPong() async throws {
        try await self.handle.send(frame: Self.pongFrame)
    }
}
