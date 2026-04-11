//
//  NOCAlert.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/14/26.
//

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
typealias NOCAlertInternal = UIAlertController
#endif

#if canImport(AppKit)
typealias NOCAlertInternal = NSAlert
#endif

@MainActor
class NOCAlert: NSObject, Sendable {
    let alert: NOCAlertInternal
    
#if canImport(UIKit)
    var title: String? {
        get { alert.title }
        set { alert.title = newValue }
    }
    
    var message: String? {
        get { alert.message }
        set { alert.message = newValue }
    }
#endif
#if canImport(AppKit)
    private weak var window: NSWindow?
    private var buttons: [NSButton: (() -> Void)] = [:]
    
    var title: String? {
        get { alert.messageText }
        set { alert.messageText = newValue ?? "" }
    }
    
    var message: String? {
        get { alert.informativeText }
        set { alert.informativeText = newValue ?? "" }
    }
#endif
    
    override init() {
        self.alert = NOCAlertInternal()
        
#if canImport(AppKit)
        // show app icon
        self.alert.icon = NSApp.applicationIconImage
#endif
        
        super.init()
    }
    
#if canImport(UIKit)
    func addButton(title: String, action: @escaping () -> Void) {
        alert.addAction(UIAlertAction(title: title, style: .default) { _ in
            action()
        })
    }
    
    @MainActor
    func present(to viewModel: UIViewController) async {
        await withCheckedContinuation { continuation in
            viewModel.present(alert, animated: true) {
                continuation.resume()
            }
        }
    }
#endif
#if canImport(AppKit)
    func addButton(title: String, action: @escaping () -> Void) {
        let button = alert.addButton(withTitle: title)
        button.target = self
        button.action = #selector(handleButtonAction(_:))
        
        self.buttons[button] = action
    }
    
    @MainActor
    func present(to nsWindow: NSWindow) async {
        self.window = nsWindow
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: nsWindow) { _ in
                // HACK: 곧바로 resume를 호출하면 다른 시트가 안 뜨는 문제 있음
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    continuation.resume()
                }
            }
        }
    }

    /// 특정 창(Window) 없이 독립적인 모달로 알림을 표시해야 할 때 사용합니다.
    ///
    /// 내부적으로 1x1 크기의 투명한 더미(Dummy) `NSWindow`를 생성하여 화면 중앙에 배치한 후,
    /// 해당 창을 부모로 삼아 시트(Sheet) 형태로 알림을 표시합니다.
    /// 알림이 닫히면 더미 창은 자동으로 정리(close)됩니다.
    @MainActor
    func present() async {
        // 앱을 맨 앞으로 가져와서 알림이 묻히지 않게 함
        NSApp.activate(ignoringOtherApps: true)

        // 1. 1x1 크기의 투명한 더미 윈도우 생성
        let dummyRect = NSRect(x: 0, y: 0, width: 1, height: 1)
        let dummyWindow = NSWindow(
            contentRect: dummyRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        
        dummyWindow.isOpaque = false
        dummyWindow.backgroundColor = .clear
        dummyWindow.hasShadow = false
        dummyWindow.level = .floating // 다른 창들보다 위로 오도록
        
        // 2. 윈도우를 화면 중앙으로 이동
        dummyWindow.center()
        
        // 3. 윈도우를 화면에 표시 (보이지는 않지만 responder chain에 참여하기 위함)
        dummyWindow.makeKeyAndOrderFront(nil)
        
        
        // 4. 기존 present(to:) 로직을 활용하여 이 더미 윈도우에 시트 띄우기
        // (이 때, 내부적으로 self.window가 dummyWindow로 설정됩니다.)
        await self.present(to: dummyWindow)

        // 5. 더미 윈도우를 화면에서 제거 (해제는 ARC가 처리)
        dummyWindow.orderOut(nil)
    }
    
    @objc
    func handleButtonAction(_ sender: NSButton) {
        buttons[sender]?()
        self.window?.endSheet(alert.window)
    }
#endif

}

