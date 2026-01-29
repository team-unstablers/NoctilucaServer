//
//  AddressBarFocusPhase.swift
//  NoctilucaClient
//

import SwiftUI

/// AddressBar의 포커스 상태를 나타내는 상태 머신
enum AddressBarFocusPhase: Equatable {
    /// 기본 상태: 레이블 표시
    case idle
    /// 포커스 획득 중: 애니메이션 진행
    case focusingIn
    /// 편집 중: 텍스트필드 활성
    case editing
    /// 포커스 해제 중: 애니메이션 진행
    case focusingOut

    // MARK: - Computed Properties for Animation

    /// 레이블 텍스트의 불투명도
    var labelTextOpacity: CGFloat {
        switch self {
        case .idle, .focusingOut:
            return 1.0
        case .focusingIn, .editing:
            return 0.0
        }
    }

    /// 텍스트필드의 불투명도
    var textFieldOpacity: CGFloat {
        switch self {
        case .idle, .focusingOut:
            return 0.0
        case .focusingIn, .editing:
            return 1.0
        }
    }

    /// 인디케이터 영역의 불투명도
    var indicatorOpacity: CGFloat {
        switch self {
        case .idle:
            return 1.0
        case .focusingIn, .editing, .focusingOut:
            return 0.0
        }
    }

    /// 포커스 테두리 스케일
    var focusBorderScale: CGFloat {
        switch self {
        case .idle, .focusingOut:
            return 1.5
        case .focusingIn:
            return 1.5  // 시작점, 애니메이션으로 1.0으로 전환
        case .editing:
            return 1.0
        }
    }

    /// 포커스 상태인지 여부
    var isFocused: Bool {
        switch self {
        case .idle, .focusingOut:
            return false
        case .focusingIn, .editing:
            return true
        }
    }
}
