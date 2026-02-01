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
    private var positionSubscription: AnyCancellable? = nil
    private var cursorSubscription: AnyCancellable? = nil

    weak var channel: ProjectionChannel? = nil
    
    init() {
    }
    
    deinit {
        self.positionSubscription?.cancel()
        self.cursorSubscription?.cancel()
    }
    
    @MainActor
    func setup() {
        let positionSubscription = cursorStateHolder.$cursorPosition
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(1000 / 60), scheduler: RunLoop.main)
            .sink { [weak self] position in
                guard let channel = self?.channel else {
                    return
                }
                
                Task {
                    try? await channel.sendCursorPositionEvent(position)
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
        
        
        self.positionSubscription = positionSubscription
        self.cursorSubscription   = cursorSubscription
    }
    
    func destroy() {
        self.positionSubscription?.cancel()
        self.positionSubscription = nil
        
        self.cursorSubscription?.cancel()
        self.cursorSubscription = nil
    }
}
