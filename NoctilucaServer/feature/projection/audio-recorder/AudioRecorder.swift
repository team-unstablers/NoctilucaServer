//
//  SessionProjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation

import CoreVideo
import AVFoundation

import SiriusKit

enum AudioRecorderSource: Hashable, Sendable {
    /// 디스플레이 ID.
    /// -1로 설정하는 경우 기본 디스플레이를 의미합니다.
    /// -2로 설정하는 경우 전체 디스플레이 영역을 의미합니다.
    case desktopSession
    case applicationAudioPID(pid: pid_t)
    case applicationAudioBundleID(bundleID: String)
    case microphone(deviceID: String)
}

struct AudioRecorderArgs {
    let source: AudioRecorderSource
    let codec: SiriusKit.AudioCodec
}

enum AudioRecorderPrepareError: LocalizedError {
    /// source를 resolve할 수 없거나 올바르지 않음
    case invalidSource
    
    /// 권한 부족
    case permissionDenied
    
    case internalError
}

protocol AudioRecorderDelegate: AnyObject, Sendable {
    func audioRecorderDidStart(_ recorder: any AudioRecorder)
    func audioRecorder(_ recorder: any AudioRecorder, didStopWithError error: Error?)
    func audioRecorder(_ recorder: any AudioRecorder, didCaptureFrame frameData: CMSampleBuffer)
}

/// NOTE: 본체 프로토콜에 Sendable 필요. 사유는 `ScreenRecorder` 주석 참조.
protocol AudioRecorder: AnyObject, Identifiable, Sendable {
    var id: UUID { get }

    var queue: DispatchQueue { get }
    var delegate: AudioRecorderDelegate? { get set }

    func prepare(with args: AudioRecorderArgs) async throws

    func start() async throws
    func stop() async throws
}

