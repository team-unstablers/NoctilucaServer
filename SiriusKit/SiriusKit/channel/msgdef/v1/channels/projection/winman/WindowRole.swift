//
//  WindowRole.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation

public struct WindowRole: RawRepresentable, Equatable, Hashable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
   
    /// 알 수 없는 역할
    public static let unknown = Self(rawValue: 0)
    
    /// 일반 윈도우
    public static let normal = Self(rawValue: 1)
    /// 다이얼로그 윈도우
    public static let dialog = Self(rawValue: 2)
    /// 툴팁 윈도우
    public static let tooltip = Self(rawValue: 3)
    /// 메뉴
    public static let menu = Self(rawValue: 4)
    
    /// 알림 윈도우
    public static let notification = Self(rawValue: 5)
}
