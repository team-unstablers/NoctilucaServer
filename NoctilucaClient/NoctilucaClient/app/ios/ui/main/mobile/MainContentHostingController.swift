//
//  MainContentHostingController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/21/26.
//

#if canImport(UIKit)
import Foundation
import UIKit
import Combine

import SwiftUI

@MainActor
final class MainContentHostingController: UIHostingController<AnyView> {

    private let viewModel: SessionWindowViewModel
    private let settingsStore: SettingsStore

    private var addressBarHostingController: UIHostingController<AnyView>?
    private var proxyView: ToolbarGeometryProxyView?

    private var phaseCancellable: AnyCancellable?
    private var fullscreenCancellable: AnyCancellable?

    /// pointer lock 여부. RootViewController에서 설정됨
    var isPointerLocked: Bool = false {
        didSet {
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }

    override var prefersPointerLocked: Bool {
        return isPointerLocked
    }

    override var prefersStatusBarHidden: Bool {
        return viewModel.isFullscreen
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return viewModel.isFullscreen
    }

    init(viewModel: SessionWindowViewModel, settingsStore: SettingsStore) {
        self.viewModel = viewModel
        self.settingsStore = settingsStore

        let contentView = UIKitMainWindow()
            .environmentObject(viewModel)
            .environmentObject(viewModel.contactSheetCoordinator)
            .environmentObject(settingsStore)

        super.init(rootView: AnyView(contentView))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        setupAddressBarTitleView()
        observePhaseChanges()
        observeFullscreenState()
    }

    // MARK: - AddressBar TitleView

    private func setupAddressBarTitleView() {
        let addressBarView = MainToolbarAddressBar(
            viewModel: viewModel,
            settingsStore: settingsStore,
            focusBinding: nil
        )

        let hostingVC = UIHostingController(rootView: AnyView(addressBarView))
        hostingVC.view.backgroundColor = .clear
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = true
        addressBarHostingController = hostingVC

        let proxy = ToolbarGeometryProxyView()
        proxy.geometryUpdateHandler = { [weak hostingVC] globalFrame in
            guard let floatingView = hostingVC?.view else { return }
            UIView.animate(withDuration: 0.3) {
                floatingView.frame = globalFrame
            }
        }

        // DEBUG
        proxy.backgroundColor = .clear
        // proxy.layer.opacity = 0.25

        proxy.translatesAutoresizingMaskIntoConstraints = true
        proxy.heightAnchor.constraint(equalToConstant: 38).isActive = true
        proxy.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true

        navigationItem.titleView = proxy
        proxyView = proxy
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachAddressBarToWindow()
        startObservingNavigationBar()
        
        UIView.animate(withDuration: 0.3) {
            self.addressBarHostingController?.view.isHidden = false
            self.addressBarHostingController?.view.layer.opacity = 1.0
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.addressBarHostingController?.view.layer.opacity = 0.0
        self.addressBarHostingController?.view.isHidden = true
    }

    private func attachAddressBarToWindow() {
        guard let hostingVC = addressBarHostingController,
              let window = view.window,
              hostingVC.view.superview != window
        else { return }

        window.addSubview(hostingVC.view)
    }

    private func startObservingNavigationBar() {
        guard let navController = navigationController as? RootViewController else { return }
        proxyView?.observe(navController.navigationBar, keyPath: "bounds")
    }

    // MARK: - Phase Observation

    private func observePhaseChanges() {
        phaseCancellable = viewModel.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.updateNavigationItems(phase: phase)
            }
    }

    private func observeFullscreenState() {
        fullscreenCancellable = viewModel.$isFullscreen
            .receive(on: RunLoop.main)
            .sink { [weak self] isFullscreen in
                self?.addressBarHostingController?.view.isHidden = isFullscreen
            }
    }

    private func updateNavigationItems(phase: MainWindowPhase) {
        switch phase {
        case .newConnection:
            navigationItem.leftBarButtonItems = nil
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "plus.app"),
                    style: .plain,
                    target: self,
                    action: #selector(addNewContact)
                ),
                UIBarButtonItem(
                    image: UIImage(systemName: "gearshape"),
                    style: .plain,
                    target: self,
                    action: #selector(openSettings)
                ),
            ]

        case .connecting:
            navigationItem.leftBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "xmark"),
                    style: .plain,
                    target: self,
                    action: #selector(stopSession)
                ),
            ]
            navigationItem.rightBarButtonItems = nil

        case .connected:
            navigationItem.leftBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "xmark"),
                    style: .plain,
                    target: self,
                    action: #selector(stopSession)
                ),
            ]
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
                    style: .plain,
                    target: self,
                    action: #selector(enterFullscreen)
                ),
                UIBarButtonItem(
                    image: UIImage(systemName: "display.2"),
                    style: .plain,
                    target: self,
                    action: #selector(switchDisplay)
                ),
            ]
        }
    }

    // MARK: - Actions

    @objc private func openSettings() {
        guard let navController = navigationController as? RootViewController else { return }
        navController.pushSettings()
    }

    @objc private func addNewContact() {
        viewModel.contactSheetCoordinator.presentContactEditor(for: nil)
    }

    @objc private func stopSession() {
        Task { @MainActor in
            await viewModel.stopSession()
        }
    }

    @objc private func switchDisplay() {
        viewModel.shouldPresentDisplaySwitchSheet = true
    }

    @objc private func enterFullscreen() {
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.isFullscreen = true
        }
    }
}

#endif
