//
//  MenuShortcutRedirector.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/23/26.
//

#if os(macOS)
import AppKit

import SiriusKitClient

/// 메인 메뉴의 알려진 `NSMenuItem` 들에서 `keyEquivalent`를 동적으로 비우거나 복원하여,
/// `⌘W`/`⌘Q` 같은 시스템 단축키가 `NSMenu`에 의해 선소비되지 않고
/// `GCKeyboard` 경로로 흘러 원격 호스트로 전달될 수 있도록 한다.
@MainActor
final class MenuShortcutRedirector {
    private static let logger = NoctilucaLogger(category: "MenuShortcutRedirector")

    private struct Entry {
        weak var item: NSMenuItem?
        let originalKeyEquivalent: String
        let originalModifierMask: NSEvent.ModifierFlags
    }

    /// `action` selector 기준 allowlist.
    /// 메뉴의 title/keyEquivalent는 로컬라이즈 / 변경에 취약하므로 selector로 고정한다.
    private static let redirectableSelectors: Set<Selector> = [
        #selector(NSWindow.performClose(_:)),
        #selector(NSApplication.terminate(_:)),
        #selector(NSWindow.performMiniaturize(_:)),
        #selector(NSApplication.hide(_:)),
        #selector(NSWindow.toggleFullScreen(_:)),
        #selector(AppDelegate.openNewMainWindow(_:)),
        #selector(AppDelegate.showSettingsWindow(_:)),
    ]

    private var entries: [Entry] = []
    private var isActive: Bool = false

    /// 메뉴 트리를 훑어 allowlist 대응 아이템을 캡처한다.
    /// `setupMainMenu()` 직후 1회 호출.
    func install(in mainMenu: NSMenu) {
        entries.removeAll(keepingCapacity: true)
        collect(from: mainMenu)
        Self.logger.debug("collected \(self.entries.count) redirectable menu item(s)")
    }

    private func collect(from menu: NSMenu) {
        for item in menu.items {
            if let action = item.action,
               Self.redirectableSelectors.contains(action),
               !item.keyEquivalent.isEmpty {
                entries.append(Entry(
                    item: item,
                    originalKeyEquivalent: item.keyEquivalent,
                    originalModifierMask: item.keyEquivalentModifierMask
                ))
            }
            if let submenu = item.submenu {
                collect(from: submenu)
            }
        }
    }

    /// 활성화 시 allowlist 아이템의 `keyEquivalent`를 비우고,
    /// 비활성화 시 원본 값으로 복원한다.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active

        for entry in entries {
            guard let item = entry.item else { continue }
            if active {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            } else {
                item.keyEquivalent = entry.originalKeyEquivalent
                item.keyEquivalentModifierMask = entry.originalModifierMask
            }
        }

        Self.logger.debug("active=\(active), mutated \(self.entries.count) item(s)")
    }
}
#endif
