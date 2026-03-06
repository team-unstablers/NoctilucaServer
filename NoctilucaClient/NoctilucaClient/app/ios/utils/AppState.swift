//
//  AppState.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/6/26.
//

#if os(iOS)

import Foundation
import Combine

import UIKit

enum AppState {
    case background
    case foreground
}

class AppStateHolder: ObservableObject {
    static let shared = AppStateHolder()
    
    @Published
    var state: AppState = .foreground
    
    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.state = .foreground
                
                if DeviceKind.current == .iPhone {
                    AppNotification.backgroundSessionActive.dismiss()
                }
            }
            .store(in: &cancellables)
        
        // willResignActive에 붙이면 iPad에서 멀티태스킹 할때 화면이 깜박거리는 경우가 있음
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.state = .background
                
                if DeviceKind.current == .iPhone {
                    if NOCAudioEngine.shared.activeNodes != 0 {
                        AppNotification.backgroundSessionActive.post()
                    }
                }
            }
            .store(in: &cancellables)
    }
}

#endif
