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
    private var stateSubscription: AnyCancellable? = nil
    private var cursorSubscription: AnyCancellable? = nil

    weak var channel: ProjectionChannel? = nil
    
    init() {
    }
    
    deinit {
        self.stateSubscription?.cancel()
        self.cursorSubscription?.cancel()
    }
    
    @MainActor
    func setup() {
        let stateSubscription = cursorStateHolder.$cursorState
            .receive(on: RunLoop.main)
            .throttle(for: .milliseconds(1000 / 60), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] state in
                guard let channel = self?.channel else {
                    return
                }
                
                guard let state else {
                    return
                }
                
                Task {
                    try? await channel.sendCursorPositionEvent(state)
                }
            }
        
        let cursorSubscription = cursorStateHolder.$cursorHash
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let channel = self?.channel else {
                    return
                }
                
                Task {
                    try? await channel.sendCursorImageEvent()
                }
            }
        
        
        self.stateSubscription = stateSubscription
        self.cursorSubscription = cursorSubscription
    }
    
    func destroy() {
        self.stateSubscription?.cancel()
        self.stateSubscription = nil
        
        self.cursorSubscription?.cancel()
        self.cursorSubscription = nil
    }
}
