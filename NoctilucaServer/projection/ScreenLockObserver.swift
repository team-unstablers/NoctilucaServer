//
// Created by Gyuhwan Park on 2023/02/04.
//

import Foundation
import Combine

import Quartz

import SiriusKit

@MainActor
class ScreenLockObserver: ObservableObject {
    static let shared = ScreenLockObserver()
    
    private let logger = NoctilucaLogger(category: "projection.ScreenLockObserver")
    private let notificationCenter = DistributedNotificationCenter.default
    
    @Published
    private(set) var isScreenLocked: Bool = false
    
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        startObserve()
        forceUpdate()
    }

    @MainActor
    deinit {
        stopObserve()
    }
    
    func forceUpdate() {
        let locked = CGSessionUtil.isScreenLocked()
        if locked != isScreenLocked {
            logger.debug("forceUpdate: isScreenLocked changed to \(locked)")
            isScreenLocked = locked
        }
    }

    private func startObserve() {
        notificationCenter.publisher(for: NSNotification.Name("com.apple.screenIsLocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                
                if self.isScreenLocked {
                    return
                }
                
                self.isScreenLocked = true
            }
            .store(in: &cancellables)
        
         notificationCenter.publisher(for: NSNotification.Name("com.apple.screenIsUnlocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                
                if !self.isScreenLocked {
                    return
                }
                
                self.isScreenLocked = false
            }
            .store(in: &cancellables)
    }

    private func stopObserve() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
