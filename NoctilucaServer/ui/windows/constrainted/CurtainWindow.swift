//
//  CurtainWindow.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Cocoa

/// 커튼 윈도우
class CurtainWindow: NSWindow, ConstraintedNSWindow {
    // 초기화 메서드를 커스텀하여 편하게 만들기 (선택 사항)
    required init(to screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless], // 테두리 없음!
            backing: .buffered,
            defer: false
        )
        
        // 기본 설정
        self.level = .screenSaver // 최상단
        self.backgroundColor = .black
        self.isOpaque = true
        self.hidesOnDeactivate = false // 다른 앱으로 포커스가 넘어가도 사라지지 않음
        
        // SwiftUI 뷰를 내용으로 넣기
        /*
        let curtainView = CurtainMessageView() // SwiftUI View
        window.contentViewController = NSHostingController(rootView: curtainView)
        
        window.orderFront(nil)
        curtainWindows.append(window)
         */
    }
    
    // --------------------------------------------------------
    // 여기가 핵심: 서브클래싱을 하는 이유
    // --------------------------------------------------------
    
    // 1. 테두리가 없어도 키보드 입력을 받을 수 있게 허용
    override var canBecomeKey: Bool {
        return true
    }
    
    // 2. 테두리가 없어도 메인 윈도우가 될 수 있게 허용
    override var canBecomeMain: Bool {
        return true
    }
    
    // (옵션) 3. ESC 키를 누르면 잠금 해제 시도 로직 등을 넣을 수 있음
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // 53 is ESC
            print("ESC 눌림: 잠금 해제 로직 실행")
            // 여기서 델리게이트나 콜백을 호출
        } else {
            super.keyDown(with: event)
        }
    }
}

