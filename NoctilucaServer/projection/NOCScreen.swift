//
//  NOCScreen.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/4/26.
//

import Foundation
import CoreGraphics

import AppKit

/// '제정신인' 디스플레이 정보를 나타냅니다.
///
/// # 왜 '제정신'인가
///
/// NOCScreen은 X11 좌표계를 기준으로 계산됩니다.
/// - NOCScreen의 (0, 0)은 그냥 전체 뷰포트의 (0, 0)입니다. NSScreen의 (0, 0)은 메인 디스플레이의 좌측 하단입니다.
/// - NOCScreen의 y축은 아래로 증가합니다. 반면 NSScreen의 y축은 위로 증가합니다.
///
struct NOCScreen: Identifiable, Hashable, Equatable {
    /// 디스플레이 ID.
    let id: CGDirectDisplayID
    
    /// 뷰포트의 프레임.
    /// origin = 좌측 상단
    /// size = 뷰포트 사이즈 (포인트 단위)
    let frame: CGRect
    
    /// '실제' 디스플레이 해상도 (픽셀 단위)
    let displayResolution: CGSize
    
    /// 디스플레이의 스케일 팩터 (@1x, @2x, ...)
    let scaleFactor: CGFloat
    
    /// FIXME: 가급적 쓰지 말 것
    let backingNSScreen: NSScreen?
    
    
    init(id: CGDirectDisplayID, frame: CGRect, displayResolution: CGSize, backingNSScreen: NSScreen? = nil) {
        self.id = id
        self.frame = frame
        self.displayResolution = displayResolution
        
        let scaleFactorX = displayResolution.width / frame.size.width
        let scaleFactorY = displayResolution.height / frame.size.height
        
        if (scaleFactorX != scaleFactorY) {
            // TODO: 진짜 이럴 일 별로 없겠지만 만약 있으면 경고를 뱉어야 함
        }
        
        self.scaleFactor = scaleFactorX
        self.backingNSScreen = backingNSScreen
    }
    
    /// HACK: backingNSScreen을 비교하지 않는다
    static func ==(lhs: NOCScreen, rhs: NOCScreen) -> Bool {
        return lhs.id == rhs.id &&
               lhs.frame == rhs.frame &&
               lhs.displayResolution == rhs.displayResolution &&
               lhs.scaleFactor == rhs.scaleFactor
    }
    
    /// HACK: backingNSScreen을 해시하지 않는다
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(frame)
        hasher.combine(displayResolution)
        hasher.combine(scaleFactor)
    }
}

extension NOCScreen {
    /// 'Intermediate' Global Frame을 생성한다
    /// Global Frame은 맞지만, CoreGraphics / NSScreen 좌표계이다. (Main Display의 좌측 하단이 (0, 0))
    static func produceIntermediateGlobalFrame(from screens: [NSScreenLike]) -> CGRect {
        return screens.reduce(CGRect.null) { $0.union($1.frame) }
    }
    
    /// X11-Like한 Global Frame을 생성한다
    /// X11-Like한 좌표계를 사용한다. (GUI 세션의 전체 뷰포트의 좌상단이 (0, 0))
    static func produceGlobalFrame(from screens: [NSScreenLike]) -> CGRect {
        var globalFrame = produceIntermediateGlobalFrame(from: screens)
        
        // (x: -320, -240, w: 1920, 1080) -> (x: 0, y: 0, w: 1920, 1080)
        globalFrame.origin.x = 0
        globalFrame.origin.y = 0
        
        return globalFrame
    }
    
    init?(from nsScreen: NSScreenLike, intermediateGlobalFrame: CGRect) {
        guard let displayID = nsScreen.compatibleDisplayID else {
            // fatalError("[WTF] NOCScreen.init(from:): NSScreen.compatibleDisplayID is nil")
            return nil
        }
        
        // 실제 디스플레이 해상도 가져오기
        var displayResolution = nsScreen.frame.size
        
        if let displayMode = CGDisplayCopyDisplayMode(displayID) {
            let pixelWidth = displayMode.pixelWidth
            let pixelHeight = displayMode.pixelHeight
            
            displayResolution = CGSize(width: pixelWidth, height: pixelHeight)
        }
        
        let frame = nsScreen.frame
        
        // NSScreen 좌표계를 NOCScreen 좌표계로 변환
        // - 기준: 전체 뷰포트(globalFrame) 좌측 상단이 (0, 0)
        // - y축: 아래로 증가
        let nocOrigin = CGPoint(
            x: frame.minX - intermediateGlobalFrame.minX,
            y: intermediateGlobalFrame.maxY - frame.maxY
        )
       
        let nocFrame = CGRect(origin: nocOrigin, size: frame.size)
        
        self.init(id: displayID, frame: nocFrame, displayResolution: displayResolution, backingNSScreen: nsScreen as? NSScreen)
    }

}
