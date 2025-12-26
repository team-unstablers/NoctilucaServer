//
//  WindowInfoFlags.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation

struct WindowRole: RawRepresentable, Equatable, Hashable {
    let rawValue: UInt32
    
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
   
    /// 일반 윈도우
    static let normal = Self(rawValue: 1)
    /// 다이얼로그 윈도우
    static let dialog = Self(rawValue: 2)
    /// 툴팁 윈도우
    static let tooltip = Self(rawValue: 3)
    /// 메뉴
    static let menu = Self(rawValue: 4)
    
    /// 알림 윈도우
    static let notification = Self(rawValue: 5)
}
