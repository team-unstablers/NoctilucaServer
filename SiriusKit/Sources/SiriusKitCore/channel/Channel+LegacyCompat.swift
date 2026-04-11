//
//  Channel+LegacyCompat.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 4/10/26.
//

import Foundation
internal import SwiftProtobuf

internal import Atomics


public protocol ChannelEventConsumer: AnyObject, Sendable {
    func handleChannelReady() async
    func handleFrame(frame: SiriusFrame) async throws
    func handleError(error: Error) async
    func handleStreamClose() async
}

/// 일단 당장 모든걸 갈아 엎을 수는 없잖아요.
public struct ChannelEventCompatBridge<Consumer: ChannelEventConsumer>: ~Copyable, Sendable {
    private unowned let consumer: Consumer
    private unowned let handle: ChannelHandle
    
    private let eventConsumerTask: Task<Void, Never>?
    
    public init(consumer: Consumer, handle: ChannelHandle) {
        self.consumer = consumer
        self.handle = handle
        
        self.eventConsumerTask = Task.detached(priority: .userInitiated) { [weak consumer, handle] in
            for await event in handle.events {
                switch event {
                case .ready:
                    await consumer?.handleChannelReady()
                case .frameReceived(let frame):
                    do {
                        try await consumer?.handleFrame(frame: frame)
                    } catch {
                        // TOOD: logging
                    }
                case .error(let error):
                    await consumer?.handleError(error: error)
                case .closed:
                    await consumer?.handleStreamClose()
                }
            }
        }
    }
    
    deinit {
        self.eventConsumerTask?.cancel()
    }
}

