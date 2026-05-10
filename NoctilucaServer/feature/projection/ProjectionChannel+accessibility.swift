//
//  ProjectionChannel+accessibility.swift
//  NoctilucaServer
//

import Foundation
import CoreGraphics
@preconcurrency import ApplicationServices

import SiriusKit

extension ProjectionChannel {

    // MARK: - GetAccessibilityTree

    /// 활성 AppStream 세션의 메뉴바(또는 특정 서브트리) 스냅샷을 반환한다.
    /// `nodeId`가 생략되면 현재 활성 AppStream 세션의 메뉴바 루트를 반환한다.
    func handleGetAccessibilityTreeRequest(_ request: GetAccessibilityTreeRequest) async throws {
        // 특정 노드 요청 — 레지스트리에서 pid 조회
        if let nodeId = request.nodeId {
            let resolution = await MainActor.run {
                (AppMenuRegistry.shared.element(for: nodeId),
                 AppMenuRegistry.shared.pid(for: nodeId))
            }

            guard let element = resolution.0, let pid = resolution.1 else {
                try await self.handle.send(opcode: .getAccessibilityTreeResponse, message: GetAccessibilityTreeResponse(
                    requestId: request.requestId,
                    success: false,
                    errorMessage: "Unknown nodeId",
                    rootNode: nil
                ))
                return
            }

            let subtree = await MainActor.run {
                AccessibilityTreeBuilder(pid: pid, maxDepth: -1)
                    .snapshot(subtreeRoot: element, parentId: nil)
            }

            try await self.handle.send(opcode: .getAccessibilityTreeResponse, message: GetAccessibilityTreeResponse(
                requestId: request.requestId,
                success: true,
                errorMessage: nil,
                rootNode: subtree
            ))
            return
        }

        // 루트 요청 — 활성 AppStream 세션의 메뉴바
        guard let session = await state.currentAppStreamSession() else {
            try await self.handle.send(opcode: .getAccessibilityTreeResponse, message: GetAccessibilityTreeResponse(
                requestId: request.requestId,
                success: false,
                errorMessage: "No active AppStream session",
                rootNode: nil
            ))
            return
        }

        // CFEqual 기반 UUID 재사용 정책이므로 prune 없이 snapshot 호출.
        // 같은 UI 요소는 같은 UUID를 반환해 이전 스냅샷의 UUID가 그대로 유효하게 유지된다.
        let rootNode = await MainActor.run { () -> AccessibilityNode? in
            guard let appSession = DesktopContextManager.shared.activeSessions[session.pid] else {
                return nil
            }
            return appSession.snapshotMenuBar(depth: 2)
        }

        guard let root = rootNode else {
            try await self.handle.send(opcode: .getAccessibilityTreeResponse, message: GetAccessibilityTreeResponse(
                requestId: request.requestId,
                success: false,
                errorMessage: "Menu bar unavailable",
                rootNode: nil
            ))
            return
        }

        try await self.handle.send(opcode: .getAccessibilityTreeResponse, message: GetAccessibilityTreeResponse(
            requestId: request.requestId,
            success: true,
            errorMessage: nil,
            rootNode: root
        ))
    }

    // MARK: - Subscribe

    func handleSubscribeAccessibilityTreeUpdatesRequest(_ request: SubscribeAccessibilityTreeUpdatesRequest) async throws {
        guard let session = await state.currentAppStreamSession() else {
            try await self.handle.send(opcode: .subscribeAccessibilityTreeUpdatesResponse, message: SubscribeAccessibilityTreeUpdatesResponse(
                requestId: request.requestId,
                subscriptionId: UUID(),
                success: false,
                errorMessage: "No active AppStream session"
            ))
            return
        }

        let subscriptionId = UUID()
        let pid = session.pid
        let eventMask = request.eventMask

        // 메뉴바 변경 콜백: DCM이 새 스냅샷을 전달해주면 AccessibilityTreeUpdateEvent로 push
        let menuHandlerId = await desktopContextManager.subscribeMenuEvents(pid: pid) { [weak self] rootNode in
            guard let self else { return }
            // eventMask 체크: childrenChanged가 꺼져있으면 스킵
            if eventMask.rawValue != 0 && !eventMask.contains(.childrenChanged) {
                return
            }
            Task { [weak self] in
                try? await self?.sendAccessibilityTreeUpdateEvent(
                    subscriptionId: subscriptionId,
                    eventType: .childrenChanged,
                    nodeId: rootNode.id,
                    updatedNode: rootNode
                )
            }
        }

        // popup(컨텍스트) 메뉴 콜백: open/close 를 일반 AccessibilityTreeUpdateEvent 로 변환해 push.
        // 메뉴바와 라이프사이클이 다르므로 debounce 가 없고, AppStream 가상 디스플레이에서 popup 이
        // ScreenCaptureKit 출력에 안 잡히는 macOS 26.4 회귀를 우회하는 native 경로의 송신 측이다.
        let contextMenuHandlerId = await desktopContextManager.subscribeContextMenuEvents(pid: pid) { [weak self] event in
            guard let self else { return }
            switch event {
            case .opened(let tree, let hostBounds, let triggerWindowID):
                // popup open 은 nodeAdded 로 매핑한다.
                if eventMask.rawValue != 0 && !eventMask.contains(.nodeAdded) {
                    return
                }
                let annotated = Self.annotateAsPopup(
                    tree,
                    hostBounds: hostBounds,
                    triggerWindowID: triggerWindowID
                )
                Task { [weak self] in
                    try? await self?.sendAccessibilityTreeUpdateEvent(
                        subscriptionId: subscriptionId,
                        eventType: .nodeAdded,
                        nodeId: annotated.id,
                        updatedNode: annotated
                    )
                }
            case .closed(let menuID):
                // popup close 는 nodeRemoved 로 매핑한다.
                if eventMask.rawValue != 0 && !eventMask.contains(.nodeRemoved) {
                    return
                }
                Task { [weak self] in
                    try? await self?.sendAccessibilityTreeUpdateEvent(
                        subscriptionId: subscriptionId,
                        eventType: .nodeRemoved,
                        nodeId: menuID,
                        updatedNode: nil
                    )
                }
            }
        }

        let info = ProjectionChannelState.AccessibilitySubscriptionInfo(
            subscriptionId: subscriptionId,
            pid: pid,
            rootNodeId: request.nodeId,
            eventMask: eventMask,
            maxDepth: request.maxDepth,
            menuEventHandlerId: menuHandlerId,
            contextMenuEventHandlerId: contextMenuHandlerId
        )

        guard await state.addAccessibilitySubscription(info) else {
            await desktopContextManager.unsubscribeMenuEvents(id: menuHandlerId)
            await desktopContextManager.unsubscribeContextMenuEvents(id: contextMenuHandlerId)
            try await self.handle.send(opcode: .subscribeAccessibilityTreeUpdatesResponse, message: SubscribeAccessibilityTreeUpdatesResponse(
                requestId: request.requestId,
                subscriptionId: subscriptionId,
                success: false,
                errorMessage: "Failed to register subscription"
            ))
            return
        }

        try await self.handle.send(opcode: .subscribeAccessibilityTreeUpdatesResponse, message: SubscribeAccessibilityTreeUpdatesResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId,
            success: true,
            errorMessage: nil
        ))
    }

    // MARK: - Unsubscribe

    func handleUnsubscribeAccessibilityTreeUpdatesRequest(_ request: UnsubscribeAccessibilityTreeUpdatesRequest) async throws {
        let removed = await state.removeAccessibilitySubscription(id: request.subscriptionId)

        if let removed {
            await desktopContextManager.unsubscribeMenuEvents(id: removed.menuEventHandlerId)
            await desktopContextManager.unsubscribeContextMenuEvents(id: removed.contextMenuEventHandlerId)
        }

        try await self.handle.send(opcode: .unsubscribeAccessibilityTreeUpdatesResponse, message: UnsubscribeAccessibilityTreeUpdatesResponse(
            requestId: request.requestId,
            subscriptionId: request.subscriptionId,
            isSuccess: removed != nil
        ))
    }

    // MARK: - DispatchAction

    func handleDispatchActionRequest(_ request: DispatchActionRequest) async throws {
        let element = await MainActor.run {
            AppMenuRegistry.shared.element(for: request.targetNodeId)
        }

        guard let element else {
            try await self.handle.send(opcode: .dispatchActionResponse, message: DispatchActionResponse(
                requestId: request.requestId,
                success: false,
                errorMessage: "Unknown targetNodeId"
            ))
            return
        }

        // 액션 별 AX action 매핑.
        // - .activate : kAXPressAction (메뉴 항목 활성화 등)
        // - .cancel   : kAXCancelAction (popup 메뉴 dismiss 등)
        let axActionName: CFString
        switch request.actionType {
        case .activate:
            axActionName = kAXPressAction as CFString
        case .cancel:
            axActionName = kAXCancelAction as CFString
        default:
            try await self.handle.send(opcode: .dispatchActionResponse, message: DispatchActionResponse(
                requestId: request.requestId,
                success: false,
                errorMessage: "Unsupported actionType: \(request.actionType.rawValue)"
            ))
            return
        }

        let axResult: AXError = await MainActor.run {
            AXUIElementPerformAction(element, axActionName)
        }

        if axResult == .success {
            try await self.handle.send(opcode: .dispatchActionResponse, message: DispatchActionResponse(
                requestId: request.requestId,
                success: true,
                errorMessage: nil
            ))
        } else {
            try await self.handle.send(opcode: .dispatchActionResponse, message: DispatchActionResponse(
                requestId: request.requestId,
                success: false,
                errorMessage: "AX \(axActionName as String) failed: \(axResult.rawValue)"
            ))
        }
    }

    // MARK: - Push Events

    /// Subscribe된 클라이언트에게 `AccessibilityTreeUpdateEvent`를 송신한다.
    func sendAccessibilityTreeUpdateEvent(
        subscriptionId: UUID,
        eventType: AccessibilityUpdateType,
        nodeId: UUID,
        updatedNode: AccessibilityNode?
    ) async throws {
        guard await state.lifecycleState == .active else { return }
        try await self.handle.send(opcode: .accessibilityTreeUpdateEvent, message: AccessibilityTreeUpdateEvent(
            subscriptionId: subscriptionId,
            eventType: eventType,
            nodeId: nodeId,
            updatedNode: updatedNode
        ))
    }

    // MARK: - Helpers

    /// popup 메뉴 트리의 루트 노드 metadata 에 popup 식별 정보를 주입한다.
    /// 클라이언트는 metadata `app.noctiluca.server.popup == "true"` 로 일반 메뉴 노드와 구분한다.
    /// `bounds` 필드는 AccessibilityTreeBuilder 가 이미 host 절대 좌표로 채워두므로 별도 보존 안 함.
    nonisolated private static func annotateAsPopup(
        _ node: AccessibilityNode,
        hostBounds: CGRect,
        triggerWindowID: WindowID?
    ) -> AccessibilityNode {
        var metadata = node.metadata
        metadata["app.noctiluca.server.popup"] = "true"
        if let triggerWindowID {
            metadata["app.noctiluca.server.popup.triggerWindowId"] = "\(triggerWindowID)"
        }
        return AccessibilityNode(
            id: node.id,
            parentId: node.parentId,
            role: node.role,
            hint: node.hint,
            bounds: node.bounds,
            localBounds: node.localBounds,
            description: node.description,
            value: node.value,
            snapshot: node.snapshot,
            attributes: node.attributes,
            metadata: metadata,
            children: node.children
        )
    }
}
