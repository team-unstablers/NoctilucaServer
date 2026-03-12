//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import AppKit
import Combine
import SwiftUI
import UserNotifications

import SiriusKit
import SwiftMsQuicHelper

import Sparkle

import Inject

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let server = NoctilucaServer.shared
    private var settingsWindowController: AppKitSettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var licensingWindowController: LicensingWindowController?
    private var aboutAppWindowController: AboutAppWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var trayMenu: NSMenu?
    private let sessionListItem = NSMenuItem()
    private let sessionListViewModel = ClientSessionListViewModel()
    private let startStopItem = NSMenuItem(title: String(localized: "menu.start-server", defaultValue: "서버 시작"), action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: String(localized: "menu.settings", defaultValue: "설정"), action: nil, keyEquivalent: ",")
    private let checkUpdatesItem = NSMenuItem(title: String(localized: "menu.check-updates", defaultValue: "업데이트 확인"), action: nil, keyEquivalent: "")
    private let licensingItem = NSMenuItem(title: String(localized: "menu.register-license", defaultValue: "라이선스 등록하기…"), action: nil, keyEquivalent: "")
    private let aboutItem = NSMenuItem(title: String(localized: "menu.about", defaultValue: "Noctiluca Server에 대하여"), action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: String(localized: "menu.quit", defaultValue: "종료"), action: nil, keyEquivalent: "q")

#if DEBUG
    private let showOnboardingWindowItem = NSMenuItem(title: "Show Onboarding Window", action: nil, keyEquivalent: "")
#endif

    static func main() {
        let app = NSApplication.shared
        
        pleaseDontDisassembleThisAppImBeggingYou("please", "please", "please")

        // ignore SIGPIPE to prevent app from crashing when trying to write to a closed socket
        signal(SIGPIPE, SIG_IGN);

        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // load MsQuic
        _ = MsQuicLoader.shared
        
        InjectConfiguration.animation = .interactiveSpring()

        TCCUtil.shared.requestAccess(for: .notifications)
        
        UNUserNotificationCenter.current().delegate = self
        
        setupMainMenu()
        setupStatusItem()
        bindServerState()
        updateMenuState()

        if getuid() != 0 && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow(nil)
        }
        
        // 라이선스 로드 (비동기, 결과에 상관없이 앱은 계속 실행)
        Task {
            await LicenseManager.shared.loadLicense()
            await MainActor.run { updateLicensingMenuState() }

            let licenseState = await LicenseManager.shared.validationState
            if (licenseState == .unlicensed || licenseState == .expired),
               UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                await MainActor.run { showLicensingWindow(nil) }
            }

            await LicenseManager.shared.startPeriodicExpirationCheck()

            if server.settings.general.autoStart {
                self.startServer(nil)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .licenseValidationStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                let state = await LicenseManager.shared.validationState
                if state == .expired {
                    await MainActor.run {
                        self?.showLicensingWindow(nil)
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        sessionListViewModel.refresh(from: server)
        updateMenuState()
        updateLicensingMenuState()
    }

    @objc
    func showOnboardingWindow(_ sender: Any?) {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController()
        }

        DispatchQueue.main.async {
            self.onboardingWindowController?.showWindow(nil)
            self.onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc
    func showLicensingWindow(_ sender: Any?) {
        if licensingWindowController == nil {
            licensingWindowController = LicensingWindowController()
        }

        DispatchQueue.main.async {
            self.licensingWindowController?.showWindow(nil)
            self.licensingWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc
    func showAboutAppWindow(_ sender: Any?) {
        if aboutAppWindowController == nil {
            aboutAppWindowController = AboutAppWindowController()
        }

        DispatchQueue.main.async {
            self.aboutAppWindowController?.showWindow(nil)
            self.aboutAppWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc
    func showSettingsWindow(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = AppKitSettingsWindowController()
        }

        DispatchQueue.main.async {
            self.settingsWindowController?.showWindow(nil)
            self.settingsWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = NoctilucaMeta.productName
        }

        let menu = NSMenu()
        menu.delegate = self

        setupSessionListView()

        startStopItem.target = self

        settingsItem.target = self
        settingsItem.action = #selector(showSettingsWindow(_:))
        licensingItem.target = self
        licensingItem.action = #selector(showLicensingWindow(_:))
        licensingItem.isHidden = true
        aboutItem.target = self
        aboutItem.action = #selector(showAboutAppWindow(_:))
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
        menu.addItem(licensingItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(checkUpdatesItem)
#if DEBUG
        menu.addItem(showOnboardingWindowItem)
#endif
        menu.addItem(aboutItem)
        menu.addItem(quitItem)

        statusItem.menu = menu

        self.statusItem = statusItem
        self.trayMenu = menu
    }

    private func bindServerState() {
        server.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)

        server.$clients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)
    }

    private func setupSessionListView() {
        sessionListViewModel.bind(to: server)
        sessionListViewModel.disconnectHandler = { [weak self] sessionIDs in
            self?.disconnectSessions(sessionIDs)
        }

        let listView = ClientSessionListView(viewModel: sessionListViewModel)
        let hostingView = NSHostingView(rootView: listView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        sessionListItem.view = hostingView
    }

    private func disconnectSessions(_ sessionIDs: Set<UUID>) {
        for sessionID in sessionIDs {
            guard let session = server.clients[sessionID] else { continue }
            Task {
                await session.closeWithGoodbye(code: .successful, message: nil)
            }
        }
    }

    private func updateMenuState() {
        switch server.state {
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

    private func updateLicensingMenuState() {
        Task {
            let state = await LicenseManager.shared.validationState
            await MainActor.run {
                licensingItem.isHidden = (state == .valid)
            }
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
