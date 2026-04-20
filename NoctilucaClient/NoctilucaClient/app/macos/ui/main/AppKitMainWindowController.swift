//
//  AppKitMainWindowController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)
import Foundation

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppKitMainWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: SessionWindowViewModel
    private let toolbarController: MainToolbar
    var onClose: ((AppKitMainWindowController) -> Void)?

    private weak var mainWindow: NSWindow?
    
    private var subDisplayWindowManager: SubDisplayWindowManager?
    private var appStreamWindowManager: AppStreamWindowManager?
    private var debugWindowController: AppKitDebugWindowController?
    private var debugWindowCancellable: AnyCancellable?
    
    init(settingsStore: SettingsStore) {
        self.viewModel = SessionWindowViewModel()
        
        viewModel.bind(settingsStore: settingsStore)
        viewModel.loadContacts()
        
        self.toolbarController = MainToolbar(viewModel: viewModel, settingsStore: settingsStore)
        
        let contentView = MainWindowRootView(viewModel: viewModel)
            .environmentObject(settingsStore)
            .environmentObject(viewModel.contactSheetCoordinator)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = [.minSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.title = NoctilucaMeta.productName
        window.minSize = NSSize(width: 640, height: 480)
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NoctilucaClient.MainWindow")
        window.center()
        
        super.init(window: window)
        
        viewModel.mainWindowController = self
        window.delegate = self
        
        self.window = window

        toolbarController.attach(to: window)

        // viewModel이 @Observable로 전환되어 `$remoteSession` publisher가 없어졌으므로
        // observeChanges 헬퍼로 프로퍼티 변경을 추적한다.
        observeChanges { [weak self] in
            guard let self else { return }
            let session = self.viewModel.remoteSession
            if let session {
                self.subDisplayWindowManager = SubDisplayWindowManager(remoteSession: session)
                self.appStreamWindowManager = AppStreamWindowManager(remoteSession: session)
                self.viewModel.appStreamWindowManager = self.appStreamWindowManager
                session.appStreamWindowManager = self.appStreamWindowManager

                self.viewModel.onDetachDisplay = { [weak self] displayID in
                    try await self?.subDisplayWindowManager?.spawn(for: displayID)
                }
                self.updateDebugWindow(session: session)
            } else {
                self.subDisplayWindowManager?.destroyAll()
                self.subDisplayWindowManager = nil
                self.appStreamWindowManager?.destroyAll()
                self.appStreamWindowManager = nil
                self.viewModel.appStreamWindowManager = nil
                self.viewModel.onDetachDisplay = nil
                self.debugWindowController?.close()
                self.debugWindowController = nil
            }
        }

        debugWindowCancellable = SettingsStore.shared.$settings
            .compactMap { $0?.misc.showDebugWindow }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] showDebugWindow in
                guard let self else { return }
                if showDebugWindow {
                    if let session = self.viewModel.remoteSession {
                        self.updateDebugWindow(session: session)
                    }
                } else {
                    self.debugWindowController?.close()
                    self.debugWindowController = nil
                }
            }
    }

    private func updateDebugWindow(session: RemoteSession) {
        guard SettingsStore.shared.settings.misc.showDebugWindow else { return }
        guard let parentWindow = self.window else { return }

        if debugWindowController == nil {
            debugWindowController = AppKitDebugWindowController()
        }
        debugWindowController?.show(for: session, parentWindow: parentWindow)
    }

    func windowWillClose(_ notification: Notification) {
        debugWindowController?.close()
        debugWindowController = nil

        subDisplayWindowManager?.destroyAll()
        subDisplayWindowManager = nil
        
        appStreamWindowManager?.destroyAll()
        appStreamWindowManager = nil

        let viewModel = self.viewModel
        if viewModel.remoteSession != nil {
            Task { @MainActor in
                await viewModel.stopSession(force: true)
            }
        }

        onClose?(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        return [.autoHideToolbar, .autoHideMenuBar, .fullScreen]
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.remoteSession?.hidio?.session.activateSession()
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.remoteSession?.hidio?.session.deactivateSession()
    }
}



#endif
