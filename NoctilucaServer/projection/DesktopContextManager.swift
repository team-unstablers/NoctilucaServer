//
//  WindowManager.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/28/25.
//

/*
<prompt>
 
1. 이 클래스들의 정의를 보고 살을 채워줄 수 있어? (실제 구현체 말고 프로토콜과 기본 클래스 정의)
 - AppSubscription: 특정 앱을 감시하는 구독
 - WindowManagerOrSpy: 시스템에서 실행중인 앱들을 감시하는 매니저 또는 스파이
2. 네이밍 추천좀 해줘
 - 일단은 `WindowManager`이나 `WindowSpy`같은걸 생각하고 있음
 
# 무슨 용도냐면...
- macOS용 원격 제어 소프트웨어를 만들고 있는데, App / Window 단위의 원격 제어를 구상하고 있음. (like RemoteApp in Microsoft RDP)
- 접근성 API나 CGWindow API를 이용해서 특정 앱의 윈도우들을 감시하고 제어하는 기능이 필요함.
</prompt>
 */

import Darwin

import Foundation

enum AppIdentifier {
    case bundleID(bundleName: String)
    case processID(pid: pid_t, processName: String?)
}

struct WindowInfo {
    let windowID: Int
    let title: String
    let isMain: Bool
    let isOnScreen: Bool
    let bounds: CGRect
    let position: CGPoint
    // TODO: 모니터 ID
    
    let appIdentifier: AppIdentifier
    let metadata: [String: Any]
}

enum AppMenuItem {
    case action(title: String, shortcut: String?, identifier: Int)
    case submenu(title: String, submenu: AppMenuRoot)
    case separator
}

struct AppMenuRoot {
    let items: [AppMenuItem]
}

protocol AppSubscriptionDelegate: AnyObject {
    /// 앱이 종료되었음을 감지했을 때 호출됩니다.
    func appSubscriptionDidDetectTermination(_ subscription: AppSubscription)
    
    /// 앱 감시 중 오류가 발생했을 때 호출됩니다.
    func appSubscription(_ subscription: AppSubscription, didEncounterError error: any Error)
    
    /// 앱이 포커스를 가졌음을 감지했을 때 호출됩니다.
    func appSubscriptionDidDetectGotFocus(_ subscription: AppSubscription)
    
    /// 앱이 포커스를 잃었음을 감지했을 때 호출됩니다.
    func appSubscriptionDidDetectLostFocus(_ subscription: AppSubscription)
    
    func appSubscriptionDidDetectMenuChange(_ subscription: AppSubscription, newMenu: AppMenuRoot)
    
    // 이것들 WindowSubscription으로 옮겨야 하나?
    func appSubscriptionDidDetectWindowMove(_ subscription: AppSubscription, windowID: Int, newPosition: CGPoint)
    func appSubscriptionDidDetectWindowResize(_ subscription: AppSubscription, windowID: Int, newSize: CGSize)
    func appSubscriptionDidDetectWindowTitleChange(_ subscription: AppSubscription, windowID: Int, newTitle: String)
    
    /// 앱이 새 윈도우를 열었음을 감지했을 때 호출됩니다.
    func appSubscription(_ subscription: AppSubscription, didDetectNewWindow windowID: Int)
    
    /// 앱이 윈도우를 닫았음을 감지했을 때 호출됩니다.
    func appSubscription(_ subscription: AppSubscription, didDetectClosedWindow windowID: Int)
}

/** 앱을 감시하는 subscription */
final class AppSubscription {
    private(set) var windowInfos: [Int: WindowInfo] = [:]
    var activeWindowID: Int? {
        nil
    }
    
    weak var delegate: AppSubscriptionDelegate?
    
    let identifier: AppIdentifier
    
    init(identifier: AppIdentifier) {
        self.identifier = identifier
    }
    
    func focusApp() throws {}

    func refreshWindowInfos() throws {}
    
    func focusWindow(windowID: Int) throws {}
    func closeWindow(windowID: Int) throws {}
    func bringAllWindowsToFront() throws {}
    
    func terminate() throws { }
    func updateMenu() throws {}
}

protocol WindowManagerDelegate {
    /// 앱이 실행되었음을 감지했을 때 호출됩니다.
    func windowManagerDidDetectAppLaunch(_ manager: WindowManagerOrSpy, identifier: AppIdentifier)
    
    /// 현재 포커스된 앱이 변경되었을 때 호출됩니다.
    func windowManagerDidDetectFocusChange(_ manager: WindowManagerOrSpy, identifier: AppIdentifier)
}

class WindowManagerOrSpy {
    init() {
    }

    // ...
}
