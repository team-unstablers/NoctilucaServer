//
//  AppDelegate.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if os(macOS)
import AppKit
import Combine

import SiriusKitClient

#if UNLEASHED_EDITION
import Sparkle
#endif

@objc
protocol EditMenuActions {
    func redo(_ sender: AnyObject)
    func undo(_ sender: AnyObject)
}

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore.shared
    private var mainWindowControllers: [AppKitMainWindowController] = []
    private var settingsWindowController: AppKitSettingsWindowController?
    private var aboutAppWindowController: AppKitAboutAppWindowController?

    /// AppStream에서 원격 메뉴로 스왑하기 전의 원본 메뉴. AppStream이 key resign 시 이 메뉴로 복구한다.
    private(set) var originalMainMenu: NSMenu?

    /// contained mode에서 originalMainMenu 에 inject 한 NSMenuItem (submenu = 호스트 앱 메뉴 트리).
    /// AppStream 세션이 active 이지만 AppStream window 가 key 가 아닌 동안 노출된다.
    private var containedRemoteMenuItem: NSMenuItem?

    private let menuShortcutRedirector = MenuShortcutRedirector()
    private var settingsCancellable: AnyCancellable?
    private var keyWindowObservers: [NSObjectProtocol] = []

    static func main() {
        let app = NSApplication.shared
        
        // ignore SIGPIPE to prevent app from crashing when trying to write to a closed socket
        signal(SIGPIPE, SIG_IGN);

        let delegate = AppDelegate()
        app.delegate = delegate
        
        // 2. 앱 실행 (Run Loop 시작)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        SiriusLogger.configure(
            minimumLevel: .trace
        )
        
#if DEBUG
        if NoctilucaMeta.isSwiftUIPreview {
            return
        }
#endif
        
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()

        if let mainMenu = NSApp.mainMenu {
            menuShortcutRedirector.install(in: mainMenu)
        }
        subscribeShortcutRedirectionTriggers()

        openNewMainWindow(nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let clientManager = NoctilucaClientManager.shared

        guard clientManager.hasActiveClients else {
            return .terminateNow
        }

        Task { @MainActor in
            await clientManager.shutdownAllClients()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openNewMainWindow(nil)
        }
        return true
    }
    
    @objc
    @MainActor
    func openNewMainWindow(_ sender: Any?) {
        let controller = AppKitMainWindowController(settingsStore: settingsStore)
        controller.onClose = { [weak self] closedController in
            self?.mainWindowControllers.removeAll { $0 === closedController }
            self?.reevaluateShortcutRedirection()
        }
        controller.onRemoteSessionChanged = { [weak self] in
            self?.reevaluateShortcutRedirection()
        }
        mainWindowControllers.append(controller)

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        reevaluateShortcutRedirection()
    }
    
    @objc
    func showSettingsWindow(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = AppKitSettingsWindowController(settingsStore: settingsStore)
        }
        
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc
    func showAboutPanel(_ sender: Any?) {
        // NSApp.orderFrontStandardAboutPanel(sender)
        if aboutAppWindowController == nil {
            aboutAppWindowController = AppKitAboutAppWindowController()
        }
        
        aboutAppWindowController?.showWindow(nil)
        aboutAppWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// AppStream이 활성화되었을 때 `NSApp.mainMenu`를 원격 앱 메뉴로 교체한다.
    /// 원본 메뉴는 `originalMainMenu`에 보관하며, `restoreOriginalMainMenu()`로 복구할 수 있다.
    func installRemoteMainMenu(_ menu: NSMenu) {
        if originalMainMenu == nil {
            originalMainMenu = NSApp.mainMenu
        }
        NSApp.mainMenu = menu
    }

    /// 원격 메뉴 스왑을 해제하고 원본으로 복귀한다.
    func restoreOriginalMainMenu() {
        guard let original = originalMainMenu else { return }
        NSApp.mainMenu = original
    }

    /// contained mode 진입: originalMainMenu 의 index 1 위치에 호스트 앱 메뉴 NSMenuItem 을 inject 한다.
    /// 이미 inject 된 항목이 있으면 먼저 제거 후 새로 inject 한다.
    func installContainedRemoteMenu(item: NSMenuItem) {
        if originalMainMenu == nil {
            originalMainMenu = NSApp.mainMenu
        }
        guard let menu = originalMainMenu else { return }

        if let existing = containedRemoteMenuItem, menu.items.contains(existing) {
            menu.removeItem(existing)
        }

        let insertIndex = min(1, menu.numberOfItems)
        menu.insertItem(item, at: insertIndex)
        containedRemoteMenuItem = item
    }

    /// contained mode 해제: originalMainMenu 에서 inject 했던 NSMenuItem 을 제거한다.
    func removeContainedRemoteMenu() {
        guard let item = containedRemoteMenuItem else { return }
        if let menu = originalMainMenu, menu.items.contains(item) {
            menu.removeItem(item)
        }
        containedRemoteMenuItem = nil
    }

    private func subscribeShortcutRedirectionTriggers() {
        settingsCancellable = settingsStore.$settings
            .map { $0?.input.redirectKnownShortcuts ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reevaluateShortcutRedirection()
            }

        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reevaluateShortcutRedirection()
                }
            }
            keyWindowObservers.append(observer)
        }
    }

    private func reevaluateShortcutRedirection() {
        let enabled = settingsStore.settings.input.redirectKnownShortcuts
        let keyWindow = NSApp.keyWindow
        let mainKeyActive = mainWindowControllers.contains { controller in
            controller.window === keyWindow && controller.hasActiveRemoteSession
        }
        menuShortcutRedirector.setActive(enabled && mainKeyActive)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        let appName = NoctilucaMeta.productName
        
        let aboutItem = NSMenuItem(title: String(localized: "menu.about", defaultValue: "Noctiluca Navigator에 대하여"), action: #selector(showAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
#if UNLEASHED_EDITION
        let checkUpdateItem = NSMenuItem(title: String(localized: "menu.check_for_updates", defaultValue: "업데이트 확인…"), action: nil, keyEquivalent: "")
        
        checkUpdateItem.target = AppUpdater.shared.updaterController
        checkUpdateItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))

        appMenu.addItem(checkUpdateItem)
#endif
        
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: String(localized: "menu.settings", defaultValue: "Noctiluca Navigator 설정…"), action: #selector(showSettingsWindow(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: String(localized: "menu.services", defaultValue: "서비스"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: String(localized: "menu.hide_app", defaultValue: "Noctiluca Navigator 가리기"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: String(localized: "menu.hide_others", defaultValue: "기타 가리기"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: String(localized: "menu.show_all", defaultValue: "모두 보기"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "menu.quit_app", defaultValue: "Noctiluca Navigator 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        
        let fileMenu = NSMenu(title: String(localized: "menu.file", defaultValue: "파일"))
        fileMenuItem.submenu = fileMenu
        
        let newWindowItem = NSMenuItem(title: String(localized: "menu.new_window", defaultValue: "새 윈도우"), action: #selector(openNewMainWindow(_:)), keyEquivalent: "n")
        newWindowItem.target = self
        fileMenu.addItem(newWindowItem)
        
        let closeWindowItem = NSMenuItem(title: String(localized: "menu.close_window", defaultValue: "윈도우 닫기"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeWindowItem)
        
        /*
        let closeAllItem = NSMenuItem(title: "Close All", action: #selector(NSApplication.closeAllWindows(_:)), keyEquivalent: "w")
        closeAllItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(closeAllItem)
         */
        
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        
        let editMenu = NSMenu(title: String(localized: "menu.edit", defaultValue: "편집"))
        editMenuItem.submenu = editMenu

        let undoItem = NSMenuItem(title: String(localized: "menu.undo", defaultValue: "실행 취소"), action: #selector(EditMenuActions.undo(_:)), keyEquivalent: "z")
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: String(localized: "menu.redo", defaultValue: "다시 실행"), action: #selector(EditMenuActions.redo(_:)), keyEquivalent: "Z")
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: String(localized: "menu.cut", defaultValue: "잘라내기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: String(localized: "menu.copy", defaultValue: "복사하기"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: String(localized: "menu.paste", defaultValue: "붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(pasteItem)

        let deleteItem = NSMenuItem(title: String(localized: "menu.delete", defaultValue: "삭제"), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(deleteItem)

        let selectAllItem = NSMenuItem(title: String(localized: "menu.select_all", defaultValue: "전체 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(selectAllItem)
        
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        
        let viewMenu = NSMenu(title: String(localized: "menu.view", defaultValue: "보기"))
        viewMenuItem.submenu = viewMenu

        let enterFullScreenItem = NSMenuItem(title: String(localized: "menu.enter_full_screen", defaultValue: "전체 화면 시작"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        enterFullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(enterFullScreenItem)
        
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        
        let windowMenu = NSMenu(title: String(localized: "menu.window", defaultValue: "윈도우"))
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let minimizeItem = NSMenuItem(title: String(localized: "menu.minimize", defaultValue: "최소화"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: String(localized: "menu.zoom", defaultValue: "확대/축소"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoomItem)

        windowMenu.addItem(.separator())

        let bringAllToFrontItem = NSMenuItem(title: String(localized: "menu.bring_all_to_front", defaultValue: "모두 앞으로 가져오기"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(bringAllToFrontItem)
        
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        
        let helpMenu = NSMenu(title: String(localized: "menu.help", defaultValue: "도움말"))
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        let helpItem = NSMenuItem(title: String(localized: "menu.app_help", defaultValue: "Noctiluca Navigator 도움말"), action: nil, keyEquivalent: "")
        helpMenu.addItem(helpItem)
    }
}

#endif
