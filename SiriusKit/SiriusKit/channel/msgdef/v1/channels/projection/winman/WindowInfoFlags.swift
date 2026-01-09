//
//  WindowInfoFlags.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation

public struct WindowInfoFlags: OptionSet, Hashable, Equatable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let none = Self([])
    
    /// 윈도우가 현재 포커스를 받고 있습니다.
    public static let isFocused = Self(rawValue: 1 << 0)
    /// 이 윈도우는 사용자에게 보이지 않도록 설정되어 있습니다.
    public static let isHidden = Self(rawValue: 1 << 1)
    /// 이 윈도우는 타이틀 바 등의 윈도우 데코레이션을 가지고 있지 않습니다.
    public static let noWindowDecoration = Self(rawValue: 1 << 2)
    /// 이 윈도우는 작업 표시줄 (Windows, Linux) 또는 독 (macOS)에 표시되지 않습니다.
    public static let skipWindowEntry = Self(rawValue: 1 << 3)
    
    /// 윈도우가 최소화 된 상태입니다.
    public static let isMinimized = Self(rawValue: 1 << 4)
    /// 윈도우가 최대화 된 상태입니다.
    public static let isMaximized = Self(rawValue: 1 << 5)
    /// 윈도우가 전체 화면 모드로 표시되고 있습니다.
    public static let isFullscreen = Self(rawValue: 1 << 6)
    
    /// 이 윈도우는 최소화가 불가능합니다.
    public static let cannotMinimize = Self(rawValue: 1 << 8)
    /// 이 윈도우는 최대화가 불가능합니다.
    public static let cannotMaximize = Self(rawValue: 1 << 9)
    /// 이 윈도우는 전체 화면 모드로 전환할 수 없습니다.
    public static let cannotFullscreen = Self(rawValue: 1 << 10)
    
    /// 이 윈도우는 항상 위에 표시되는(topmost) 상태입니다.
    public static let isTopmost = Self(rawValue: 1 << 12)
    /// 이 윈도우는 항상 아래에 표시되는(bottommost) 상태입니다.
    public static let isBottommost = Self(rawValue: 1 << 13)
    
    /// Linux: 이 윈도우는 컴포지터를 스킵합니다.
    /// Windows: 이 윈도우는 DWM (Desktop Window Manager)을 스킵합니다. (Aero Glass 효과 등이 적용되지 않음)
    /// - 알려진 호환성 문제가 있는 애플리케이션이나, low-latency를 보장받아야 하는 애플리케이션에 설정되어 있을 수 있습니다.
    public static let skipCompositor = Self(rawValue: 1 << 16)
}
