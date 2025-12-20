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

enum ScreenRecorderSource: Hashable, Sendable {
    /// 디스플레이 ID.
    /// -1로 설정하는 경우 기본 디스플레이를 의미합니다.
    /// -2로 설정하는 경우 전체 디스플레이 영역을 의미합니다.
    case entireDisplay(displayID: Int64)
    case displayRegion(displayID: Int64, region: CGRect)
    case window(windowID: Int64)
}

extension ScreenRecorderSource {
    /// 기본(Primary) 디스플레이를 프로젝션 해야 하는지 여부를 반환합니다.
    var requiresPrimaryDisplay: Bool {
        switch self {
        case .entireDisplay(let displayID):
            return displayID == -1
        case .displayRegion(let displayID, _):
            return displayID == -1
        default:
            return false
        }
    }
    
    /// 전체 디스플레이 영역 / 전체 뷰포트를 프로젝션 해야 하는지 여부를 반환합니다.
    var requiresEntireDisplayRegion: Bool {
        #warning("TODO: ScreenCaptureKit에서 이걸 지원하지 않아서 프로토콜에서도 지원하지 않기로 했습니다")
        return false
    }
}

struct ScreenRecorderArgs {
    let source: ScreenRecorderSource
    let codec: Codec
    let flags: ProjectionSourceFlagSet
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

