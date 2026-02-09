//
//  RootViewController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/26/25.
//
#if canImport(UIKit)
import Foundation
import UIKit
import Combine

import SwiftUI

@MainActor
final class RootViewController: UIHostingController<AnyView> {

    /// FIXME: 둘이 합치던가 하세요
    var mainUIViewModel: MobileUIMainViewModel? = nil
    var mainWindowViewModel: SessionWindowViewModel? = nil
    var settingsStore: SettingsStore? = nil

    /// 포인터 락 여부를 설정합니다.
    /// true로 설정 시 포인터가 고정되지만, 전체 화면 모드에서만 동작합니다.
    var isPointerLocked: Bool = false {
        didSet {
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }

    override var prefersPointerLocked: Bool {
        return isPointerLocked
    }

    override var prefersStatusBarHidden: Bool {
        return mainWindowViewModel?.isFullscreen ?? false
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return mainWindowViewModel?.isFullscreen ?? false
    }

    private var fullscreenCancellable: AnyCancellable?

    init() {
        let mainUIViewModel = MobileUIMainViewModel()
        let mainWindowViewModel = SessionWindowViewModel()
        let settingsStore = SettingsStore.shared

        self.mainUIViewModel = mainUIViewModel
        self.mainWindowViewModel = mainWindowViewModel
        self.settingsStore = settingsStore

        mainWindowViewModel.bind(settingsStore: settingsStore)
        mainWindowViewModel.loadContacts()

        let contentView = MobileUIMainView()
            .environmentObject(mainUIViewModel)
            .environmentObject(mainWindowViewModel)
            .environmentObject(mainWindowViewModel.contactSheetCoordinator)
            .environmentObject(settingsStore)

        super.init(rootView: AnyView(contentView))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeFullscreenState()
    }

    private func observeFullscreenState() {
        guard let mainWindowViewModel else { return }

        fullscreenCancellable = mainWindowViewModel.$isFullscreen
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                UIView.animate(withDuration: 0.3) {
                    self.setNeedsStatusBarAppearanceUpdate()
                }
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
    }
}

#endif
