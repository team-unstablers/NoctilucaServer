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
final class RootViewController: UINavigationController {

    var mainWindowViewModel: SessionWindowViewModel? = nil
    var settingsStore: SettingsStore? = nil

    private var mainContentHostingController: MainContentHostingController? = nil

    /// 포인터 락 여부를 설정합니다.
    /// true로 설정 시 포인터가 고정되지만, 전체 화면 모드에서만 동작합니다.
    var isPointerLocked: Bool = false {
        didSet {
            mainContentHostingController?.isPointerLocked = isPointerLocked
        }
    }

    override var prefersPointerLocked: Bool {
        return isPointerLocked
    }

    override var childForStatusBarHidden: UIViewController? {
        return topViewController
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        return topViewController
    }

    private var fullscreenCancellable: AnyCancellable?

    init() {
        let mainWindowViewModel = SessionWindowViewModel()
        let settingsStore = SettingsStore.shared

        mainWindowViewModel.bind(settingsStore: settingsStore)
        mainWindowViewModel.loadContacts()

        let mainContentVC = MainContentHostingController(
            viewModel: mainWindowViewModel,
            settingsStore: settingsStore
        )

        super.init(rootViewController: mainContentVC)

        self.mainWindowViewModel = mainWindowViewModel
        self.settingsStore = settingsStore
        self.mainContentHostingController = mainContentVC

        mainWindowViewModel.rootViewController = self

        navigationBar.prefersLargeTitles = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeFullscreenState()
    }

    // MARK: - Settings Navigation

    func pushSettings() {
        guard let settingsStore else { return }

        let settingsView = SettingsWindow { [weak self] tab in
            self?.pushSettingsDetail(tab: tab)
        }
        .environmentObject(settingsStore)

        let hostingVC = UIHostingController(rootView: AnyView(settingsView))
        hostingVC.title = String(localized: "settings.title", defaultValue: "설정")
        pushViewController(hostingVC, animated: true)
    }

    private func pushSettingsDetail(tab: SettingsWindow.SettingsTab) {
        guard let settingsStore else { return }

        let detailView: AnyView
        switch tab {
        case .general:
            detailView = AnyView(GeneralSettingsTab().environmentObject(settingsStore))
        case .projection:
            detailView = AnyView(ProjectionSettingsTab().environmentObject(settingsStore))
        case .input:
            detailView = AnyView(InputSettingsTab().environmentObject(settingsStore))
        case .security:
            detailView = AnyView(SecuritySettingsTab().environmentObject(settingsStore))
        case .misc:
            detailView = AnyView(
                MiscSettingsTab(settings: .init(
                    get: { [settingsStore] in settingsStore.settings },
                    set: { [settingsStore] in settingsStore.settings = $0 }
                ))
                .environmentObject(settingsStore)
            )
        case .plugins:
            detailView = AnyView(PluginsSettingsTab().environmentObject(settingsStore))
        case .about:
            detailView = AnyView(AboutSettingsTab().environmentObject(settingsStore))
        }

        let hostingVC = UIHostingController(rootView: detailView)
        pushViewController(hostingVC, animated: true)
    }

    // MARK: - Fullscreen Observation

    private func observeFullscreenState() {
        guard let mainWindowViewModel else { return }

        fullscreenCancellable = mainWindowViewModel.$isFullscreen
            .receive(on: RunLoop.main)
            .sink { [weak self] isFullscreen in
                guard let self else { return }
                self.setNavigationBarHidden(isFullscreen, animated: true)
                UIView.animate(withDuration: 0.3) {
                    self.topViewController?.setNeedsStatusBarAppearanceUpdate()
                }
                self.topViewController?.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
    }
}

#endif
