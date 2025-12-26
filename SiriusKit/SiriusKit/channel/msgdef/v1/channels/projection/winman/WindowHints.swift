//
//  WindowInfoFlags.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation

struct WindowHints: OptionSet {
    let rawValue: UInt32
    
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    static let none = Self([])
    
    /// 이 윈도우는 시스템 UI의 일부입니다.
    /// 예시: 탐색 막대, 상태 표시줄, 알림 센터, IME 패널 (한글-한자 변환 / 일본어・중국어 변환 후보 등)
    static let systemUI = Self(rawValue: 1 << 0)
    
    
    /// 이 윈도우는 시스템에 의해 응답하지 않는 것으로 보고되었습니다.
    static let notResponding = Self(rawValue: 1 << 1)
    
    /// 이 윈도우는 시스템 정책에 의해 조작이 불가능할 것으로 예상됩니다. (다른 유저 세션의 윈도우, 고권한 프로세스의 윈도우, UAC 등)
    static let inaccessible = Self(rawValue: 1 << 2)
    
    /// 이 윈도우는 시스템 정책에 의해 캡처가 불가능할 것으로 예상됩니다. (DRM 보호 컨텐츠 등)
    /// @note 이 힌트는 무조건 캡처가 불가능하다는 보장이 아닙니다. 실제로 캡처는 이루어질 수 있으나, 검은 화면 등으로 나타날 수 있습니다.
    static let protectedContent = Self(rawValue: 1 << 3)
    
    /// 이 윈도우는 제 3자의 외부 DRM 솔루션, 안티-치트 솔루션 등에 의해 강력히 보호되는 것으로 보입니다.
    /// - 이 윈도우를 캡쳐하거나 원격으로 조작하려고 시도할 경우, 서버 구현체의 프로세스가 충돌하거나 강제 종료될 수도 있기 때문에 프로젝션을 권장하지 않습니다.
    /// - e.g.) AhnLab Safe Transaction, Fasoo DRM 등
    static let aggressiveProtectedContent = Self(rawValue: 1 << 4)
    
    /// 이 윈도우는 현재 다른 창에 가려져 있거나 해서 화면에 보이지 않는 상태입니다.
    static let notVisibleOnScreen = Self(rawValue: 1 << 5)
    
    /// 이 윈도우는 자주 변경되지 않는 정적 콘텐츠를 포함하고 있습니다.
    static let staticContent = Self(rawValue: 1 << 8)
    
    /// 이 윈도우는 빠르게 갱신되는 동적 컨텐츠 (예: 비디오 플레이어, 게임 등)를 포함하고 있습니다.
    static let dynamicContent = Self(rawValue: 1 << 9)
    
    /// 이 윈도우는 그림자를 포함하고 있습니다.
    /// - 윈도우 외곽에 그림자가 있는 경우에 유용합니다.
    /// - AppStream (가칭) 같은 기능을 구현할 때, 클라이언트 측에서 대신 shadow를 그리도록 할 수 있습니다.
    static let hasShadow = Self(rawValue: 1 << 12)
    
    /// 이 윈도우는 투명한 영역을 포함하고 있습니다.
    /// - border-radius가 설정되었거나, 부분적으로 투명한 UI를 포함하는 윈도우에 유용합니다.
    static let hasTransparency = Self(rawValue: 1 << 13)
    
    
}
