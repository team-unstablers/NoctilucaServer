//
//  AppMenuRegistry.swift
//  NoctilucaServer
//

import Foundation
@preconcurrency import ApplicationServices

/// Accessibility 노드 UUID와 AXUIElement 간의 매핑을 관리한다.
///
/// `DispatchActionRequest`가 도착했을 때 클라이언트가 보낸 UUID를 AXUIElement로 역매핑해
/// `AXUIElementPerformAction(kAXPressAction)`으로 이어주는 접착제 역할을 한다.
///
/// AXUIElement의 CFEqual/CFHash는 동일 UI 요소에 대해 다른 인스턴스일 경우
/// 안정적이지 않을 수 있으므로, 스냅샷마다 **새 UUID를 발급**한다.
/// 클라이언트는 `AccessibilityTreeUpdateEvent(childrenChanged)` 수신 후 재fetch해야 한다.
@MainActor
final class AppMenuRegistry {
    static let shared = AppMenuRegistry()

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    private var idToEntry: [UUID: Entry] = [:]

    private init() {}

    /// 새 UUID를 발급하고 AXUIElement에 매핑한다.
    @discardableResult
    func register(element: AXUIElement, pid: pid_t) -> UUID {
        let id = UUID()
        idToEntry[id] = Entry(element: element, pid: pid)
        return id
    }

    /// UUID로 AXUIElement를 조회한다.
    func element(for id: UUID) -> AXUIElement? {
        return idToEntry[id]?.element
    }

    /// UUID에 연결된 pid를 조회한다.
    func pid(for id: UUID) -> pid_t? {
        return idToEntry[id]?.pid
    }

    /// 특정 pid의 매핑을 모두 제거한다. (AppStream 세션 종료 또는 메뉴 스냅샷 재구축 시 호출)
    func prune(pid: pid_t) {
        idToEntry = idToEntry.filter { $0.value.pid != pid }
    }

    /// 전체 매핑을 초기화한다.
    func removeAll() {
        idToEntry.removeAll()
    }
}
