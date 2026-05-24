//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import AppKit
@preconcurrency import Combine
import SwiftUI
import UserNotifications

import SiriusKit
import SwiftMsQuic

import Sparkle

@preconcurrency import Inject

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, Sendable {
    private let server = NoctilucaServer.shared
    private var settingsWindowController: AppKitSettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var aboutAppWindowController: AboutAppWindowController?
    private let activationPolicyCoordinator = ActivationPolicyCoordinator()
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var trayMenu: NSMenu?
    private let sessionListItem = NSMenuItem()
    private let sessionListViewModel = ClientSessionListViewModel()
    private let startStopItem = NSMenuItem(title: String(localized: "menu.start-server", defaultValue: "서버 시작"), action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: String(localized: "menu.settings", defaultValue: "설정"), action: nil, keyEquivalent: ",")
    private let checkUpdatesItem = NSMenuItem(title: String(localized: "menu.check-updates", defaultValue: "업데이트 확인"), action: nil, keyEquivalent: "")
    private let earlyAccessDiscordServerItem = NSMenuItem(title: String(localized: "menu.early-access-discord", defaultValue: "얼리 액세스 사용자를 위한 Discord 서버"), action: nil, keyEquivalent: "")
    private let aboutItem = NSMenuItem(title: String(localized: "menu.about", defaultValue: "Noctiluca Server에 대하여"), action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: String(localized: "menu.quit", defaultValue: "종료"), action: nil, keyEquivalent: "q")

#if DEBUG
    private let showOnboardingWindowItem = NSMenuItem(title: "Show Onboarding Window", action: nil, keyEquivalent: "")
#endif

    static func main() {
        let app = NSApplication.shared

        // ignore SIGPIPE to prevent app from crashing when trying to write to a closed socket
        signal(SIGPIPE, SIG_IGN);

        // SIGTERM / SIGINT 수신 시 fsaccess NFS mount 를 forced unmount 후 graceful 종료.
        FSAccessSignalGuard.install()

        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // load MsQuic
        _ = MsQuicLoader.shared
        
        try? CoreGraphicsPrivate.open()
        try? SkyLightPrivate.open()

        // Sentry telemetry (opt-in, EEA/UK 제외)
        server.settings.telemetry.ensureIdentifier()
        TelemetryService.shared.startIfNeeded(settings: server.settings.telemetry)

        InjectConfiguration.animation = .interactiveSpring()

        TCCUtil.shared.requestAccess(for: .notifications)
        
        try? ApplicationServicesPrivate.open()
        try? SkyLightPrivate.open()
        
        UNUserNotificationCenter.current().delegate = self
        
        Task { @MainActor in
            setupMainMenu()
            await setupStatusItem()
            await bindServerState()
            await updateMenuState()
        }

        if getuid() != 0 && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow(nil)
        }

        Task {
            if await server.settings.general.autoStart {
                self.startServer(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        Task { @MainActor in
            await sessionListViewModel.refresh(from: server)
            await updateMenuState()
        }
    }

    @objc
    @MainActor
    func showOnboardingWindow(_ sender: Any?) {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController()
        }

        DispatchQueue.main.async {
            self.onboardingWindowController?.showWindow(nil)
            self.onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
            if let window = self.onboardingWindowController?.window {
                self.activationPolicyCoordinator.track(window)
            }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc
    @MainActor
    func showAboutAppWindow(_ sender: Any?) {
        if aboutAppWindowController == nil {
            aboutAppWindowController = AboutAppWindowController()
        }

        DispatchQueue.main.async {
            self.aboutAppWindowController?.showWindow(nil)
            self.aboutAppWindowController?.window?.makeKeyAndOrderFront(nil)
            if let window = self.aboutAppWindowController?.window {
                self.activationPolicyCoordinator.track(window)
            }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc
    @MainActor
    func showSettingsWindow(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = AppKitSettingsWindowController()
        }

        DispatchQueue.main.async {
            self.settingsWindowController?.showWindow(nil)
            self.settingsWindowController?.window?.makeKeyAndOrderFront(nil)
            if let window = self.settingsWindowController?.window {
                self.activationPolicyCoordinator.track(window)
            }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc
    func startServer(_ sender: Any?) {
        Task {
            do {
                try await server.startup()
            } catch {
                // FIXME: 알림을 쏘십시오...
                print(error.localizedDescription)
            }
        }
    }

    @objc
    func stopServer(_ sender: Any?) {
        Task {
            do {
                try await server.shutdown()
            } catch {
                // FIXME: 알림을 쏘십시오...
                print(error.localizedDescription)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            do {
                try await server.shutdown()
            } catch {
                print("shutdown failed: \(error.localizedDescription)")
            }
            TelemetryService.shared.stop()
            SiriusEventFileLogDestination.flushAll()
            SiriusFileLogDestination.flushAll()
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    @objc
    func quitApplication(_ sender: Any?) {
        NSApp.terminate(nil)
    }
    
    @objc
    func joinEarlyAccessDiscordServer(_ sender: Any?) {
        if let url = URL(string: "https://discord.gg/Nzm34Yyrys") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "\u{8}")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @MainActor
    private func setupStatusItem() async {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "TrayIconInactive")
        }

        let menu = NSMenu()
        menu.delegate = self

        await setupSessionListView()

        startStopItem.target = self

        settingsItem.target = self
        settingsItem.action = #selector(showSettingsWindow(_:))
        aboutItem.target = self
        aboutItem.action = #selector(showAboutAppWindow(_:))
        
        earlyAccessDiscordServerItem.target = self
        earlyAccessDiscordServerItem.action = #selector(joinEarlyAccessDiscordServer(_:))
        
        quitItem.target = self
        quitItem.action = #selector(quitApplication(_:))

        checkUpdatesItem.target = AppUpdater.shared.updaterController
        checkUpdatesItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        
#if DEBUG
        showOnboardingWindowItem.target = self
        showOnboardingWindowItem.action = #selector(showOnboardingWindow)
#endif

        menu.addItem(sessionListItem)
        menu.addItem(startStopItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(checkUpdatesItem)
#if DEBUG
        menu.addItem(showOnboardingWindowItem)
#endif
        menu.addItem(earlyAccessDiscordServerItem)
        menu.addItem(aboutItem)
        menu.addItem(quitItem)

        statusItem.menu = menu

        self.statusItem = statusItem
        self.trayMenu = menu
    }

    private func bindServerState() async {
        await server.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateTrayIcon()
                    await self?.updateMenuState()
                }
            }
            .store(in: &cancellables)

        await server.$clients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateTrayIcon()
                    await self?.updateMenuState()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func setupSessionListView() async {
        await sessionListViewModel.bind(to: server)
        
        sessionListViewModel.disconnectHandler = { [weak self] sessionIDs in
            Task {
                await self?.disconnectSessions(sessionIDs)
            }
        }

        let listView = ClientSessionListView(viewModel: sessionListViewModel)
        let hostingView = NSHostingView(rootView: listView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        sessionListItem.view = hostingView
    }

    private func disconnectSessions(_ sessionIDs: Set<UUID>) async {
        for sessionID in sessionIDs {
            guard let session = await server.clients[sessionID] else { continue }
            Task {
                await session.closeWithGoodbye(code: .successful, message: nil)
            }
        }
    }
    
    @MainActor
    private func updateTrayIcon() async {
        guard let button = statusItem?.button else {
            return
        }
        
        if case .idle = await self.server.state {
            button.image = NSImage(named: "TrayIconInactive")
            return
        }
        
        if await self.server.clients.isEmpty {
            button.image = NSImage(named: "TrayIcon")
        } else {
            button.image = NSImage(named: "TrayIconActive")
        }
    }

    @MainActor
    private func updateMenuState() async {
        switch await server.state {
        case .idle:
            startStopItem.title = String(localized: "menu.start-server", defaultValue: "서버 시작")
            startStopItem.action = #selector(startServer(_:))
            startStopItem.isEnabled = true
        case .preparing:
            startStopItem.title = String(localized: "menu.start-server", defaultValue: "서버 시작")
            startStopItem.action = #selector(startServer(_:))
            startStopItem.isEnabled = false
        case .running:
            startStopItem.title = String(localized: "menu.stop-server", defaultValue: "서버 중지")
            startStopItem.action = #selector(stopServer(_:))
            startStopItem.isEnabled = true
        }
    }

}


extension AppDelegate: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.sound, .banner, .list])
    }
}
