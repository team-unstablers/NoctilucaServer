//
//  CursorEventSubscription.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation
import Combine

import SiriusKit

class CursorEventSubscription {
    let id: UUID = UUID()
    
    private let cursorStateHolder = CursorStateHolder.shared
    private var subscription: AnyCancellable? = nil

    weak var channel: ProjectionChannel? = nil
    
    init() {
    }
    
    deinit {
        self.subscription?.cancel()
    }
    
    @MainActor
    func setup() {
        let subscription = cursorStateHolder.$cursorHash
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let channel = self?.channel else {
                    return
                }
                
                Task {
                    try? await channel.sendCursorEvent()
                }
            }
        
        self.subscription = subscription
    }
    
    func destroy() {
        self.subscription?.cancel()
        self.subscription = nil
    }
}
