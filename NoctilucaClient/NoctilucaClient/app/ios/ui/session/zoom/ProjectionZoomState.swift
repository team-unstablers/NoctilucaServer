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
    case cursorTracking
    case free
    
    static func defaultFor(_ touchInputMode: AppSettings.TouchInputMode) -> Self {
        switch touchInputMode {
        case .touch:
            return .free
        case .trackpad:
            return .cursorTracking
        }
    }
}

#endif
