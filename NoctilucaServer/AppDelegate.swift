//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import AppKit
import Combine
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let server = NoctilucaServer.shared
    private var settingsWindowController: AppKitSettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var trayMenu: NSMenu?
    private let sessionStatusItem = NSMenuItem(title: "현재 활성 중인 세션 없음", action: nil, keyEquivalent: "")
    private let startStopItem = NSMenuItem(title: "서버 시작", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "설정", action: nil, keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "종료", action: nil, keyEquivalent: "q")

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        TCCUtil.shared.requestAccess(for: .notifications)
        
        UNUserNotificationCenter.current().delegate = self
        
        setupStatusItem()
        bindServerState()
        updateMenuState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuState()
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
                print(error.localizedDescription)
            }
        }
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

        sessionStatusItem.isEnabled = false
        startStopItem.target = self
        
        settingsItem.target = self
        settingsItem.action = #selector(showSettingsWindow(_:))
        quitItem.target = self
        quitItem.action = #selector(quitApplication(_:))

        menu.addItem(sessionStatusItem)
        menu.addItem(startStopItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu

        self.statusItem = statusItem
        self.trayMenu = menu
    }

    private func bindServerState() {
        server.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)

        server.$clients
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuState()
            }
            .store(in: &cancellables)
    }

    private func updateMenuState() {
        sessionStatusItem.isEnabled = false

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
