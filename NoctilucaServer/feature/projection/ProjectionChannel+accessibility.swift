//
//  ProjectionChannel+accessibility.swift
//  NoctilucaServer
//

import Foundation
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

        // 메뉴 변경 콜백: DCM이 새 스냅샷을 전달해주면 AccessibilityTreeUpdateEvent로 push
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

        let info = ProjectionChannelState.AccessibilitySubscriptionInfo(
            subscriptionId: subscriptionId,
            pid: pid,
            rootNodeId: request.nodeId,
            eventMask: eventMask,
            maxDepth: request.maxDepth,
            menuEventHandlerId: menuHandlerId
        )

        guard await state.addAccessibilitySubscription(info) else {
            await desktopContextManager.unsubscribeMenuEvents(id: menuHandlerId)
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

        // 현재는 `activate` 한 종류만 지원. 다른 액션은 후속 확장 예정.
        guard request.actionType == .activate else {
            try await self.handle.send(opcode: .dispatchActionResponse, message: DispatchActionResponse(
                requestId: request.requestId,
                success: false,
                errorMessage: "Unsupported actionType: \(request.actionType.rawValue)"
            ))
            return
        }

        let axResult: AXError = await MainActor.run {
            AXUIElementPerformAction(element, kAXPressAction as CFString)
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
                errorMessage: "AX kAXPressAction failed: \(axResult.rawValue)"
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
}
