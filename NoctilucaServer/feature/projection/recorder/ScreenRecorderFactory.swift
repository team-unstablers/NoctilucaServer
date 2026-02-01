//
//  ScreenRecorder+create.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation

class ScreenRecorderFactory {
    @MainActor
    static func create(preferred type: ScreenRecorderType, queue: DispatchQueue) -> any ScreenRecorder {
        if ScreenLockObserver.shared.isScreenLocked {
            // When the screen is locked, use AVFoundation-based recorder.
            return AVFoundationScreenRecorder(queue: queue)
        }
        
        switch type {
        case .screenCaptureKit:
            return ScreenCaptureKitScreenRecorder(queue: queue)
        case .avFoundation:
            fallthrough
        default:
            return AVFoundationScreenRecorder(queue: queue)
        }
    }
}
