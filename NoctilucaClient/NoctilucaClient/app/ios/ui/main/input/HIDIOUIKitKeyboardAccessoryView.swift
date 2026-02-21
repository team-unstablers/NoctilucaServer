//
//  HIDIOUIKitKeyboardAccessoryView.swift
//  NoctilucaClient
//

#if os(iOS)

import SwiftUI
import UIKit

final class HIDIOUIKitKeyboardAccessoryView: UIInputView {
    private let hostingController: UIHostingController<AnyView>

    init(keyboard: HIDIOUIKitKeyboard) {
        let content = if (DeviceKind.current == .iPad) {
            AnyView(HIDIOUIKitKeyboardHelperView(keyboard: keyboard, isVisible: true))
        } else {
            AnyView(HIDIOUIKitKeyboardCompactHelperView(keyboard: keyboard, isVisible: true))
        }
        
        self.hostingController = UIHostingController(rootView: content)
        
        
        // FIXME: 하드 코드된 크기
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: DeviceKind.current == .iPad ? 160 : 96), inputViewStyle: .keyboard)

        self.allowsSelfSizing = true

        let hostView = hostingController.view!
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.backgroundColor = .clear
        addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostView.topAnchor.constraint(equalTo: topAnchor),
            hostView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#endif
