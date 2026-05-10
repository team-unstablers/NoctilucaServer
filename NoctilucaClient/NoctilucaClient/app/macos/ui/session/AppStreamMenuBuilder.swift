//
//  AppStreamMenuBuilder.swift
//  NoctilucaClient
//

#if os(macOS)
import Foundation
import AppKit

import SiriusKitClient

/// 원격 앱의 `AccessibilityNode` 트리를 로컬 `NSMenu`로 변환한다.
/// 서브메뉴는 사용자가 열 때 `NSMenuDelegate.menuNeedsUpdate`로 비동기 populate된다.
@MainActor
final class AppStreamMenuBuilder: NSObject, NSMenuDelegate {
    let logger = NoctilucaLogger(category: "AppStreamMenuBuilder")

    private let projectionChannel: ProjectionChannel

    /// NSMenu → AccessibilityNode.id 역매핑
    private var menuToNodeId: [ObjectIdentifier: UUID] = [:]

    /// 이미 실제 자식으로 populate된 NSMenu 집합
    private var populatedMenus: Set<ObjectIdentifier> = []

    /// 현재 populate 진행 중인 NSMenu 집합 (중복 호출 방지)
    private var populatingMenus: Set<ObjectIdentifier> = []

    init(projectionChannel: ProjectionChannel) {
        self.projectionChannel = projectionChannel
        super.init()
    }

    // MARK: - Public

    /// 호스트 메뉴바에서 앱 이름 메뉴 (보통 "Apple" 다음 첫 번째 아이템) 의 라벨을 추출한다.
    /// "Apple" wrapper 가 없으면 root.children 의 첫 번째 노드 라벨을 사용한다.
    /// 둘 다 비어있으면 nil.
    static func extractAppTitle(from root: AccessibilityNode) -> String? {
        guard !root.children.isEmpty else { return nil }
        let isMacOSMenu = root.children.first?.description == "Apple"
        let candidate = isMacOSMenu ? root.children.dropFirst().first : root.children.first
        guard let label = candidate?.description, !label.isEmpty else { return nil }
        return label
    }

    /// `buildMenu(from:)` 결과 NSMenu 를 NSMenuItem(submenu) 으로 wrap 하여 반환한다.
    /// contained mode 에서 NocClient 본 메뉴의 root 에 inject 하기 위해 사용한다.
    func buildContainedItem(from root: AccessibilityNode, appTitle: String) -> NSMenuItem {
        let menu = buildMenu(from: root)
        // wrapping NSMenu 의 title 도 appTitle 로 맞춰 둔다 (NSMenuItem submenu 의 외부 title 은
        // wrapping NSMenuItem.title 이 우선이지만, NSMenu.title 도 일관되게 유지).
        menu.title = appTitle

        let item = NSMenuItem(title: appTitle, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// 루트 메뉴바 `AccessibilityNode`를 `NSMenu`로 변환한다.
    /// 루트 노드 자체는 `NSMenu` 하나로 치환되고, 자식이 최상위 메뉴 아이템이 된다.
    func buildMenu(from root: AccessibilityNode) -> NSMenu {
        let menu = NSMenu(title: root.description)
        menu.delegate = self
        menuToNodeId[ObjectIdentifier(menu)] = root.id
        
        // 루트는 eager로 이미 children이 채워져 있다고 가정
        populatedMenus.insert(ObjectIdentifier(menu))
        
        let isMacOSMenu = root.children.first?.description == "Apple"
        
        let children = if isMacOSMenu {
            Array(root.children.dropFirst(1))
        } else {
            root.children
        }
        
        if isMacOSMenu {
            let appMenuItem = NSMenuItem()
            appMenuItem.title = "Noctiluca Navigator"
            menu.addItem(appMenuItem)
            
            let appMenu = NSMenu()
            appMenuItem.submenu = appMenu
            
            // add dummy menu
            let aboutItem = NSMenuItem(
                title: String(
                    localized: "menu.appstream.appmenu.appstream_indicator",
                    defaultValue: "AppStream 활성화됨"
                ),
                action: nil,
                keyEquivalent: ""
            )
            
            aboutItem.target = self
            appMenu.addItem(aboutItem)
        }
        
        for child in children {
            let item = buildMenuItem(from: child)
            menu.addItem(item)
        }

        return menu
    }

    // MARK: - Item Construction

    private func buildMenuItem(from node: AccessibilityNode) -> NSMenuItem {
        // role = menuGroup (separator)인 경우
        if node.role == .menuGroup {
            return NSMenuItem.separator()
        }

        let title = node.description
        let cmdChar = node.attributes["app.noctiluca.server.x-ax.cmdChar"] ?? ""
        let keyEquivalent = cmdChar.lowercased()

        let item = NSMenuItem(
            title: title,
            action: #selector(didActivateRemoteMenuItem(_:)),
            keyEquivalent: keyEquivalent
        )
        item.target = self
        item.representedObject = node.id
        item.isEnabled = !node.hint.contains(.disabled)

        // Modifier 매핑 (AXMenuItemCmdModifiers 비트 레이아웃)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = Self.modifierFlags(
                fromCmdModifiers: node.attributes["app.noctiluca.server.x-ax.cmdModifiers"]
            )
        }

        // 자식이 있을 가능성이 있으면 submenu 부착 + delegate로 lazy populate.
        //
        // submenu 존재 판단 우선순위:
        //   1. role == .menu — 메뉴 자체
        //   2. children 비어있지 않음 — 이미 트리에 포함되어 옴
        //   3. hasSubmenu hint — 서버에서 AXMenu wrapper 발견을 알린 경우.
        //      macOS AX 메뉴는 사용자가 한 번도 펼쳐보지 않은 nested submenu의 children이
        //      빈 채로 보고되는 경우가 있어, hint 없이는 ▶ 표시가 누락되어 사용자가
        //      submenu에 접근하지 못한다.
        let hasSubmenuHint = node.attributes["app.noctiluca.server.x-ax.hasSubmenu"] == "1"
        let shouldAttachSubmenu = node.role == .menu || !node.children.isEmpty || hasSubmenuHint
        if shouldAttachSubmenu {
            let submenu = NSMenu(title: title)
            submenu.delegate = self
            menuToNodeId[ObjectIdentifier(submenu)] = node.id

            if node.children.isEmpty {
                // placeholder
                submenu.addItem(Self.makeLoadingPlaceholder())
            } else {
                populatedMenus.insert(ObjectIdentifier(submenu))
                for child in node.children {
                    submenu.addItem(buildMenuItem(from: child))
                }
            }

            item.submenu = submenu
        }

        return item
    }

    private static func makeLoadingPlaceholder() -> NSMenuItem {
        let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func makeFailurePlaceholder(reason: String) -> NSMenuItem {
        let item = NSMenuItem(title: "Failed to load: \(reason)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// AX `cmdModifiers` 비트 마스크를 `NSEvent.ModifierFlags`로 변환한다.
    /// AX 관례상 `cmdChar`가 비어있지 않으면 Command가 암묵적으로 포함된다.
    ///
    /// AXMenuItemCmdModifiers 비트 레이아웃 (Apple Event macros 기반):
    /// - bit 0: Shift  (0x01)
    /// - bit 1: Option (0x02)
    /// - bit 2: Control(0x04)
    /// - bit 3: NoCommand (0x08) — 설정되면 Command 제외
    private static func modifierFlags(fromCmdModifiers raw: String?) -> NSEvent.ModifierFlags {
        guard let raw, let value = Int(raw) else {
            return [.command]
        }
        var flags: NSEvent.ModifierFlags = []
        if (value & 0x01) != 0 { flags.insert(.shift) }
        if (value & 0x02) != 0 { flags.insert(.option) }
        if (value & 0x04) != 0 { flags.insert(.control) }
        if (value & 0x08) == 0 { flags.insert(.command) }
        return flags
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let key = ObjectIdentifier(menu)
        guard !populatedMenus.contains(key) else { return }
        guard !populatingMenus.contains(key) else { return }
        guard let nodeId = menuToNodeId[key] else { return }

        populatingMenus.insert(key)

        Task { @MainActor [weak self, weak menu] in
            guard let self = self, let menu = menu else { return }
            defer { self.populatingMenus.remove(key) }

            do {
                let response = try await self.projectionChannel.getAccessibilityTree(nodeId: nodeId)
                guard response.success, let node = response.rootNode else {
                    self.replaceMenuItemsWithFailure(menu, reason: response.errorMessage ?? "unknown")
                    return
                }

                menu.removeAllItems()
                for child in node.children {
                    menu.addItem(self.buildMenuItem(from: child))
                }
                self.populatedMenus.insert(key)
            } catch {
                self.logger.warning("Failed to fetch submenu \(nodeId): \(error)")
                self.replaceMenuItemsWithFailure(menu, reason: String(describing: error))
            }
        }
    }

    private func replaceMenuItemsWithFailure(_ menu: NSMenu, reason: String) {
        menu.removeAllItems()
        menu.addItem(Self.makeFailurePlaceholder(reason: reason))
    }

    // MARK: - Invalidation

    /// 특정 nodeId에 대응하는 NSMenu의 캐시를 무효화한다. 다음 open 시 재fetch된다.
    func invalidate(nodeId: UUID) {
        // nodeId → ObjectIdentifier는 다대일 관계가 아니지만, 역매핑이 없으므로 전체 스캔
        for (oid, mappedId) in menuToNodeId where mappedId == nodeId {
            populatedMenus.remove(oid)
        }
    }

    /// 모든 캐시를 초기화한다. (예: AppStream 종료)
    func reset() {
        menuToNodeId.removeAll()
        populatedMenus.removeAll()
        populatingMenus.removeAll()
    }

    // MARK: - Action Selector

    @objc private func didActivateRemoteMenuItem(_ sender: NSMenuItem) {
        guard let nodeId = sender.representedObject as? UUID else {
            logger.warning("Menu item activated but representedObject is not UUID")
            return
        }

        // 단축키(keyEquivalent)로 invoke된 경우는 HIDIO 경로가 이미 원격 앱에 키 이벤트를
        // 전달하므로 DispatchAction을 보내면 이중 실행이 발생한다. 메뉴를 직접 클릭한
        // 경우(leftMouseUp 등)에만 DispatchAction을 전송한다.
        if let event = NSApp.currentEvent, event.type == .keyDown {
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.projectionChannel.dispatchAction(
                    targetNodeId: nodeId,
                    actionType: .activate
                )
                if !response.success {
                    self.logger.warning("DispatchAction failed: \(response.errorMessage ?? "nil")")
                }
            } catch {
                self.logger.warning("DispatchAction error: \(error)")
            }
        }
    }
}
#endif
