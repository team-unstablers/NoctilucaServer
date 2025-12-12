//
//  SessionProjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation

import CoreVideo
import AVFoundation

enum ScreenRecorderSource: Hashable, Sendable {
    case entireDisplay(displayID: UInt32)
    case displayRegion(displayID: UInt32, region: CGRect)
    case window(windowID: UInt32)
}

struct ScreenRecorderArgs {
    let source: ScreenRecorderSource
}

enum ScreenRecorderPrepareError: LocalizedError {
    /// source를 resolve할 수 없거나 올바르지 않음
    case invalidSource
    
    /// 권한 부족
    case permissionDenied
    
    case internalError
}

protocol ScreenRecorderDelegate: AnyObject {
    func screenRecorderDidStart(_ recorder: any ScreenRecorder)
    func screenRecorder(_ recorder: any ScreenRecorder, didStopWithError error: Error?)
    func screenRecorder(_ recorder: any ScreenRecorder, didCaptureFrame frameData: CMSampleBuffer)
}

protocol ScreenRecorder: AnyObject, Identifiable {
    var id: UUID { get }
    
    var queue: DispatchQueue { get set }
    var delegate: ScreenRecorderDelegate? { get set }
    
    func prepare(with args: ScreenRecorderArgs) async throws
    
    func start() async throws
    func stop() async throws
}
