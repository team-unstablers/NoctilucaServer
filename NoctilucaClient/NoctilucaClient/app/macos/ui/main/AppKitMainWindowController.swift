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

    private var subDisplayWindowManager: SubDisplayWindowManager?
    private var remoteSessionCancellable: AnyCancellable?
    
    init(settingsStore: SettingsStore) {
        self.viewModel = SessionWindowViewModel()
        
        viewModel.bind(settingsStore: settingsStore)
        viewModel.loadContacts()
        
        self.toolbarController = MainToolbar(viewModel: viewModel, settingsStore: settingsStore)
        
        let contentView = MainWindowRootView(viewModel: viewModel)
            .environmentObject(settingsStore)
            .environmentObject(viewModel.contactSheetCoordinator)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.title = NoctilucaMeta.productName
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NoctilucaClient.MainWindow")
        window.center()
        
        super.init(window: window)
        
        window.delegate = self

        toolbarController.attach(to: window)

        remoteSessionCancellable = viewModel.$remoteSession
            .receive(on: RunLoop.main)
            .sink { [weak self] session in
                guard let self else { return }
                if let session {
                    self.subDisplayWindowManager = SubDisplayWindowManager(remoteSession: session)
                    self.viewModel.onDetachDisplay = { [weak self] displayID in
                        try await self?.subDisplayWindowManager?.spawn(for: displayID)
                    }
                } else {
                    self.subDisplayWindowManager?.destroyAll()
                    self.subDisplayWindowManager = nil
                    self.viewModel.onDetachDisplay = nil
                }
            }
    }

    func windowWillClose(_ notification: Notification) {
        subDisplayWindowManager?.destroyAll()
        subDisplayWindowManager = nil

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
}



#endif
