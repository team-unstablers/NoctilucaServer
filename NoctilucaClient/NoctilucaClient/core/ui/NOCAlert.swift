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

class NOCAlert: NSObject {
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
    
    @objc
    func handleButtonAction(_ sender: NSButton) {
        buttons[sender]?()
        self.window?.endSheet(alert.window)
    }
#endif

}

