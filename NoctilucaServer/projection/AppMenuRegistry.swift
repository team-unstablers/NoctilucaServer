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
/// 같은 UI 요소에 대해서는 `CFEqual` 기반으로 UUID를 재사용한다. 스냅샷이 여러 번 반복되어도
/// 클라이언트가 가진 UUID가 무효화되지 않도록 하기 위함이다. (예: 메뉴를 열면
/// kAXMenuOpened 노티로 재스냅샷이 돌아가는 동안 사용자가 이미 캐시한 UUID로 DispatchAction을
/// 보내오는 경우)
///
/// AppStream 세션이 종료되면 `prune(pid:)`로 해당 앱의 모든 매핑을 회수한다.
@MainActor
final class AppMenuRegistry {
    static let shared = AppMenuRegistry()

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    /// UUID → Entry 정방향 매핑
    private var idToEntry: [UUID: Entry] = [:]

    /// pid 단위로 AXUIElement → UUID 역매핑. CFEqual 기반 equality 사용.
    private var elementIndex: [pid_t: [AXElementKey: UUID]] = [:]

    private init() {}

    /// 주어진 AXUIElement에 대응하는 UUID를 반환한다. 이미 등록된 요소면 기존 UUID를
    /// 재사용하고, 아니면 새 UUID를 발급한다.
    @discardableResult
    func register(element: AXUIElement, pid: pid_t) -> UUID {
        let key = AXElementKey(element: element)
        if let existing = elementIndex[pid]?[key] {
            return existing
        }
        let id = UUID()
        idToEntry[id] = Entry(element: element, pid: pid)
        elementIndex[pid, default: [:]][key] = id
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

    /// 특정 pid의 매핑을 모두 제거한다. (AppStream 세션 종료 시 호출)
    func prune(pid: pid_t) {
        if let map = elementIndex[pid] {
            for uuid in map.values {
                idToEntry.removeValue(forKey: uuid)
            }
        }
        elementIndex.removeValue(forKey: pid)
    }

    /// 전체 매핑을 초기화한다.
    func removeAll() {
        idToEntry.removeAll()
        elementIndex.removeAll()
    }
}

/// AXUIElement를 `CFEqual`/`CFHash`로 비교하는 Hashable wrapper.
private struct AXElementKey: Hashable {
    let element: AXUIElement

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }

    static func == (lhs: AXElementKey, rhs: AXElementKey) -> Bool {
        return CFEqual(lhs.element, rhs.element)
    }
}
