//
//  NSWindow+NoctilucaLayoutSwizzle.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/22/25.
//

#if os(macOS)
import Foundation
import AppKit

@objc
extension NSWindow {
    static var __NOC__swizzled_layoutIfNeeded: Bool = false
    static var __NOC__original_layoutIfNeeded: Method? = nil
    
    @objc
    static func __NOC__swizzleLayoutIfNeeded() {
        guard !__NOC__swizzled_layoutIfNeeded else {
            return
        }
        
        __NOC__swizzled_layoutIfNeeded = true

        let originalSelector = #selector(layoutIfNeeded)
        let swizzledSelector = #selector(__NOC__layoutIfNeeded)
        
        guard let originalMethod = class_getInstanceMethod(NSWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSWindow.self, swizzledSelector) else {
            return
        }
        
        __NOC__original_layoutIfNeeded = originalMethod
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
        
    }
    
    @objc
    func __NOC__layoutIfNeeded() {
        // call original method
        self.__NOC__layoutIfNeeded()
        
        // FIXME: self.class = ...
        if self.toolbar != nil {
            toolbarStyle = .unified
            titleVisibility = .hidden
        }
        
        print("\(Date.now) - layoutIfNeeded swizzled called")

        // self.centerTrafficLights()
        
        /*
        if let item = self.toolbar?.items.first(where: { $0.itemIdentifier == .nocAddressBar }) {
            if let titlebarContainerHeight = standardWindowButton(.closeButton)?.superview?.bounds.height,
               let view = item.view
            {
                let addressBarHeight = view.fittingSize.height
                let centeredY = (titlebarContainerHeight - addressBarHeight) / 2
                
                print(centeredY)
                DispatchQueue.main.async {
                    print(item.view?.frame.origin.y ?? -1)
                    if (item.view?.frame.origin.y ?? -1) != centeredY {
                        item.view?.frame.origin.y = 24
                    }
                }
            }
        }
         */
    }
    
    @objc
    func centerTrafficLights() {
        guard self.toolbar != nil else {
            // 툴바가 없으면 신호등 버튼을 굳이 정렬할 필요가 없으므로 종료
            return
        }
        // 신호등 버튼 3개 가져오기
        let trafficLightButtons: [NSButton?] = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton)
        ]
        
        // 버튼들의 부모 뷰(Titlebar Container)가 존재해야 계산 가능
        guard let titlebarContainer = trafficLightButtons.first??.superview else { return }
        
        for button in trafficLightButtons {
            guard let btn = button else { continue }
            
            // 핵심 계산: (부모 뷰 높이 - 버튼 높이) / 2
            // 이렇게 하면 수직 중앙에 위치하게 됩니다.
            let centeredY = (titlebarContainer.bounds.height - btn.frame.height) / 2
            
            // 위치 적용
            // 주의: Auto Layout 간섭을 피하기 위해 frame을 직접 수정합니다.
            btn.frame.origin.y = centeredY
        }
    }
}
#endif
