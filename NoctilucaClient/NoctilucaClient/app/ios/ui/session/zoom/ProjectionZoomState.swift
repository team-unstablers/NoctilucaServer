//
//  ProjectionZoomState.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/21/26.
//

#if os(iOS)
import Foundation

/// 줌 모드 상태 머신
/// 팔레트 버튼으로 OFF → CursorTracking → Free → OFF 순환
enum ProjectionZoomMode: Equatable, Hashable {
    case off
    case cursorTracking
    case free

    var next: ProjectionZoomMode {
        switch self {
        case .off: return .cursorTracking
        case .cursorTracking: return .free
        case .free: return .off
        }
    }
}

/// 커서 트래킹 줌이 어떻게 시작되었는지 추적.
/// 키보드 dismiss 시 자동 해제 vs 유지 결정에 사용.
enum CursorTrackingZoomTrigger: Equatable {
    /// 키보드 등장으로 자동 진입
    case keyboard
    /// 팔레트 버튼으로 수동 진입
    case manual
}
#endif
