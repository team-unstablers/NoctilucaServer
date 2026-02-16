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

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let server = NoctilucaServer.shared
    private var settingsWindowController: AppKitSettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var trayMenu: NSMenu?
    private let sessionListItem = NSMenuItem()
    private let sessionListViewModel = ClientSessionListViewModel()
    private let startStopItem = NSMenuItem(title: "서버 시작", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "설정", action: nil, keyEquivalent: ",")
    private let checkUpdatesItem = NSMenuItem(title: "업데이트 확인", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "종료", action: nil, keyEquivalent: "q")

    static func main() {
        let app = NSApplication.shared
        
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // FIXME: 아직 라이선스 시스템이 없으므로 2026년 3월 31일 이후로 앱 사용을 막도록 한다
        let expirationDate = Date(timeIntervalSince1970: 1774882800.0)
        if Date.now.timeIntervalSince1970 > expirationDate.timeIntervalSince1970 {
            let alert = NSAlert()
            alert.messageText = "테스트 기간 만료"
            alert.informativeText = "Noctiluca Server의 테스트 기간이 만료되었습니다. 최신 버전으로 업데이트해 주세요."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "확인")
            alert.runModal()
            NSApp.terminate(nil)
            
            return
        }
        
        // load MsQuic
        _ = MsQuicLoader.shared

        NSApp.setActivationPolicy(.accessory)
        
        TCCUtil.shared.requestAccess(for: .notifications)
        
        UNUserNotificationCenter.current().delegate = self
        
        setupStatusItem()
        bindServerState()
        updateMenuState()

        if getuid() != 0 && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        sessionListViewModel.refresh(from: server)
        updateMenuState()
    }

    private func showOnboardingWindow() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController()
        }

        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    func showSettingsWindow(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = AppKitSettingsWindowController()
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        quitItem.target = self
        quitItem.action = #selector(quitApplication(_:))
        
        checkUpdatesItem.target = AppUpdater.shared.updaterController
        checkUpdatesItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))

        menu.addItem(sessionListItem)
        menu.addItem(startStopItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(checkUpdatesItem)
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
            startStopItem.title = "서버 시작"
            startStopItem.action = #selector(startServer(_:))
            startStopItem.isEnabled = true
        case .preparing:
            startStopItem.title = "서버 시작"
            startStopItem.action = #selector(startServer(_:))
            startStopItem.isEnabled = false
        case .running:
            startStopItem.title = "서버 중지"
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
