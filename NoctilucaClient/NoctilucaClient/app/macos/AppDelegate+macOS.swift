//
//  AppDelegate.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if os(macOS)
import AppKit

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
class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore.shared
    private var mainWindowControllers: [AppKitMainWindowController] = []
    private var settingsWindowController: AppKitSettingsWindowController?
    private var aboutAppWindowController: AppKitAboutAppWindowController?

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
        }
        mainWindowControllers.append(controller)
        
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
