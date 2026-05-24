//
//  AccessibilityTreeBuilder.swift
//  NoctilucaServer
//

import Foundation
import CoreGraphics
@preconcurrency import ApplicationServices

import SiriusKit

/// AXUIElement 트리를 순회하여 `AccessibilityNode`로 직렬화한다.
/// 현재는 메뉴바/메뉴 아이템 전용으로 최적화되어 있다.
///
/// 각 노드마다 `AppMenuRegistry`에 UUID를 발급 등록하여, 추후 `DispatchActionRequest`로
/// 클라이언트가 노드 UUID를 돌려보내면 원본 AXUIElement를 되찾을 수 있게 한다.
@MainActor
struct AccessibilityTreeBuilder {
    /// 최대 재귀 깊이. 음수면 무제한.
    /// - 0: root만 (children 빈 배열)
    /// - 1: root + 직계 자식
    /// - 2: root + 자식 + 손자 (eager mode 권장)
    let maxDepth: Int

    let pid: pid_t

    init(pid: pid_t, maxDepth: Int) {
        self.pid = pid
        self.maxDepth = maxDepth
    }

    /// 앱의 메뉴바를 루트로 스냅샷을 만든다.
    /// - Returns: 메뉴바에 해당하는 `AccessibilityNode` (role = "menu"), 또는 메뉴바를 가져올 수 없으면 nil
    func snapshotMenuBar(appElement: AXUIElement) -> AccessibilityNode? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &value)
        guard result == .success, let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }
        let menuBar = raw as! AXUIElement
        return buildNode(element: menuBar, depth: 0, parentId: nil)
    }

    /// 임의 서브트리 스냅샷 (lazy 확장 요청에 사용).
    func snapshot(subtreeRoot element: AXUIElement, parentId: UUID?) -> AccessibilityNode {
        return buildNode(element: element, depth: 0, parentId: parentId)
    }

    // MARK: - Private

    private func buildNode(element: AXUIElement, depth: Int, parentId: UUID?) -> AccessibilityNode {
        let role = readString(element, kAXRoleAttribute as String) ?? ""
        let title = readString(element, kAXTitleAttribute as String) ?? ""
        let isEnabled = readBool(element, kAXEnabledAttribute as String) ?? true

        let mappedRole = Self.mapRole(axRole: role, title: title)

        var hint: AccessibilityNodeHint = []
        if !isEnabled {
            hint.insert(.disabled)
        }

        var attributes: [String: String] = [
            "app.noctiluca.server.x-ax.role": role
        ]

        if let cmdChar = readString(element, "AXMenuItemCmdChar"), !cmdChar.isEmpty {
            attributes["app.noctiluca.server.x-ax.cmdChar"] = cmdChar
        }
        if let cmdVirtualKey = readInt(element, "AXMenuItemCmdVirtualKey") {
            attributes["app.noctiluca.server.x-ax.cmdVirtualKey"] = String(cmdVirtualKey)
        }
        if let cmdModifiers = readInt(element, "AXMenuItemCmdModifiers") {
            attributes["app.noctiluca.server.x-ax.cmdModifiers"] = String(cmdModifiers)
        }
        if let cmdGlyph = readInt(element, "AXMenuItemCmdGlyph") {
            attributes["app.noctiluca.server.x-ax.cmdGlyph"] = String(cmdGlyph)
        }
        if let markChar = readString(element, "AXMenuItemMarkChar"), !markChar.isEmpty {
            attributes["app.noctiluca.server.x-ax.markChar"] = markChar
        }

        let bounds = readBounds(element)

        // UUID 발급 및 등록
        let id = AppMenuRegistry.shared.register(element: element, pid: pid)

        // 자식 순회: wrapper detection은 depth 제한과 무관하게 수행하여,
        // depth 한계에 도달해 children enumerate를 생략하더라도 클라이언트가 submenu 존재
        // 여부를 알 수 있도록 hint(`hasSubmenu`)를 부착한다. macOS AX 메뉴는 사용자가
        // 한 번도 펼쳐본 적 없는 nested submenu의 children이 빈 배열로 보고되는 경우가 있어,
        // children 유무만으로는 leaf 여부를 판단할 수 없기 때문이다.
        let canRecurseRole = Self.shouldRecurseInto(role: mappedRole)
        let depthOK = (maxDepth < 0 || depth < maxDepth)
        let children: [AccessibilityNode]
        if canRecurseRole {
            // macOS AX 구조상 menuItem의 자식은 단일 AXMenu wrapper를 거쳐 실제 항목들이 존재한다.
            // 트리가 불필요하게 중첩되지 않도록 wrapper를 투명하게 unwrap하여 wrapper의 children을
            // 현재 menuItem의 직접 children으로 승격시킨다.
            let rawChildren = readChildren(element)
            let unwrap = Self.unwrapMenuWrapper(
                rawChildren: rawChildren,
                parentRole: mappedRole,
                reader: readChildren
            )
            if unwrap.hasWrapper {
                attributes["app.noctiluca.server.x-ax.hasSubmenu"] = "1"
            }
            if depthOK {
                children = unwrap.children.map { child in
                    buildNode(element: child, depth: depth + 1, parentId: id)
                }
            } else {
                children = []
            }
        } else {
            children = []
        }

        return AccessibilityNode(
            id: id,
            parentId: parentId,
            role: mappedRole,
            hint: hint,
            bounds: bounds,
            localBounds: nil,
            description: title,
            value: nil,
            snapshot: nil,
            attributes: attributes,
            metadata: [:],
            children: children
        )
    }

    /// AXRole + title에서 `AccessibilityNodeRole`로 매핑.
    private static func mapRole(axRole: String, title: String) -> AccessibilityNodeRole {
        switch axRole {
        case "AXMenuBar":
            return .menu
        case "AXMenu":
            return .menu
        case "AXMenuBarItem", "AXMenuItem":
            // 제목이 없는 AXMenuItem은 separator로 취급 → menuGroup으로 매핑
            if title.isEmpty {
                return .menuGroup
            }
            return .menuItem
        default:
            // 메뉴 계통 외의 요소는 있는 그대로 두되 역직렬화 가능한 형태로
            return AccessibilityNodeRole(rawValue: axRole)
        }
    }

    /// 해당 role의 요소가 자식을 가질 수 있는지. menuItem은 보통 submenu를 자식으로 두고,
    /// menu/menuBar는 항목들을 자식으로 둔다. menuGroup(separator)은 자식 없음.
    private static func shouldRecurseInto(role: AccessibilityNodeRole) -> Bool {
        switch role {
        case .menu, .menuItem:
            return true
        case .menuGroup:
            return false
        default:
            return true
        }
    }

    /// menuItem의 자식이 정확히 하나의 AXMenu(wrapper)이면 wrapper의 children으로 대체한다.
    /// parentRole이 menuItem이 아니거나(예: 메뉴바 루트) wrapper 패턴이 아니면 원본 그대로 반환.
    ///
    /// macOS AX 메뉴 계층:
    ///   AXMenuBar (menu)
    ///     └─ AXMenuBarItem (menuItem, title="File")
    ///         └─ AXMenu (wrapper, title="")
    ///             ├─ AXMenuItem "New"
    ///             └─ AXMenuItem "Open"
    /// 위 구조에서 wrapper AXMenu를 투명 처리하여 MenuBarItem이 직접 MenuItem들을 자식으로
    /// 갖는 것처럼 트리를 평탄화한다.
    ///
    /// - Returns: 평탄화된 children 배열과 wrapper 발견 여부. wrapper가 발견되면 children이
    ///   비어있더라도(예: macOS가 아직 lazy populate하지 않은 nested submenu) 호출자는
    ///   submenu 존재를 클라이언트에 알릴 수 있다.
    private static func unwrapMenuWrapper(
        rawChildren: [AXUIElement],
        parentRole: AccessibilityNodeRole,
        reader: (AXUIElement) -> [AXUIElement]
    ) -> (children: [AXUIElement], hasWrapper: Bool) {
        guard parentRole == .menuItem else { return (rawChildren, false) }
        guard rawChildren.count == 1 else { return (rawChildren, false) }

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(rawChildren[0], kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              role == "AXMenu" else {
            return (rawChildren, false)
        }
        return (reader(rawChildren[0]), true)
    }

    // MARK: - AX Readers

    private func readString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func readBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func readInt(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func readChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func readBounds(_ element: AXUIElement) -> SRRect {
        var origin = CGPoint.zero
        var size = CGSize.zero

        if let positionValue = readAXValue(element, kAXPositionAttribute as String, type: .cgPoint) {
            AXValueGetValue(positionValue, .cgPoint, &origin)
        }
        if let sizeValue = readAXValue(element, kAXSizeAttribute as String, type: .cgSize) {
            AXValueGetValue(sizeValue, .cgSize, &size)
        }

        return SRRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    private func readAXValue(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = raw as! AXValue
        if AXValueGetType(axValue) == type {
            return axValue
        }
        return nil
    }
}
