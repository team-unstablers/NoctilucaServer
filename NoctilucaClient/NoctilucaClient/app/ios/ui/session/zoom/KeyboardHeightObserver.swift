//
//  KeyboardHeightObserver.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/21/26.
//

#if os(iOS)
import UIKit
import Combine

@MainActor
final class KeyboardHeightObserver: ObservableObject {
    @Published private(set) var keyboardHeight: CGFloat = 0
    @Published private(set) var isKeyboardVisible: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification -> CGFloat? in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                return frame?.height
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] height in
                self?.keyboardHeight = height
                self?.isKeyboardVisible = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.keyboardHeight = 0
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
    }
}
#endif
