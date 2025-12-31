//
//  ScreenCaptureKitWorkaroundDummyWindow.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Cocoa

/// ScreenCaptureKit의 제약을 우회하기 위한 더미 윈도우입니다.
/// - 특정 버전 이상의 macOS에서의 ScreenCaptureKit은, 화면 캡쳐의 exclusion 대상에 윈도우가 하나도 없을 경우 캡쳐를 허용하지 않는 제약이 있습니다.
class ScreenCaptureKitWorkaroundDummyWindow: NSWindow, ConstraintedNSWindow {
    required init(to screen: NSScreen) {
        // 1x1 픽셀을 각 화면의 좌상단에 위치시킴
        let origin = screen.frame.origin
        let rect = NSRect(x: origin.x, y: origin.y, width: 1, height: 1)
        
        super.init(
            contentRect: rect,
            // 테두리 없음
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        
        self.configure()
    }
    
    func configure() {
        self.backgroundColor = .clear
        self.alphaValue = 0.001 // 0.001도 OK (완전 0.0이면 렌더링 파이프라인에서 제외될 수 있음)
        self.ignoresMouseEvents = true // 마우스 이벤트 무시 (클릭 투과)
        
        // Mission Control에 안 뜨게 하고 모든 데스크탑 공간에 존재하게 함
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        self.animationBehavior = .none
        
        // 화면에 표시 (Key Window로는 설정하지 않음)
        self.orderFront(nil)
        
        // 혹시나 걱정하는 사람들을 위해
        self.title = "ScreenCaptureKitWorkaroundDummyWindow"
        self.subtitle = "This window is used to work around ScreenCaptureKit limitations."
    }
}

extension ScreenCaptureKitWorkaroundDummyWindow {
    static let windowManager = ConstraintedNSWindowManager<ScreenCaptureKitWorkaroundDummyWindow>()
}
