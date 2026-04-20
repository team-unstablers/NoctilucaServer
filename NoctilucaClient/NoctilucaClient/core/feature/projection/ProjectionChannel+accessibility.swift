//
//  ProjectionChannel+accessibility.swift
//  NoctilucaClient
//

import Foundation
import SiriusKitClient

extension ProjectionChannel {

    // MARK: - Get Accessibility Tree

    /// Accessibility 트리를 요청한다.
    /// - Parameter nodeId: 조회 기준 노드. `nil`이면 현재 활성 AppStream 세션의 메뉴바 루트.
    /// - Parameter flags: 추가 플래그.
    func getAccessibilityTree(
        nodeId: UUID? = nil,
        flags: GetAccessibilityTreeRequestFlags = []
    ) async throws -> GetAccessibilityTreeResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .getAccessibilityTreeRequest,
            message: GetAccessibilityTreeRequest(
                requestId: requestID,
                nodeId: nodeId,
                flags: flags
            )
        )
    }

    // MARK: - Subscribe / Unsubscribe

    /// Accessibility 트리 변경 이벤트 구독을 요청한다.
    /// - Parameters:
    ///   - nodeId: 구독할 서브트리 루트. `nil`이면 현재 활성 AppStream 세션의 메뉴바 전체.
    ///   - eventMask: 구독할 이벤트 종류 마스크. `0`이면 전체.
    ///   - maxDepth: 최대 깊이. `0`이면 무제한.
    ///   - flags: 추가 플래그.
    func subscribeAccessibilityTreeUpdates(
        nodeId: UUID? = nil,
        eventMask: AccessibilityUpdateType = [],
        maxDepth: UInt32 = 0,
        flags: GetAccessibilityTreeRequestFlags = []
    ) async throws -> SubscribeAccessibilityTreeUpdatesResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .subscribeAccessibilityTreeUpdatesRequest,
            message: SubscribeAccessibilityTreeUpdatesRequest(
                requestId: requestID,
                nodeId: nodeId,
                eventMask: eventMask,
                maxDepth: maxDepth,
                flags: flags
            )
        )
    }

    func unsubscribeAccessibilityTreeUpdates(
        subscriptionId: UUID
    ) async throws -> UnsubscribeAccessibilityTreeUpdatesResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .unsubscribeAccessibilityTreeUpdatesRequest,
            message: UnsubscribeAccessibilityTreeUpdatesRequest(
                requestId: requestID,
                subscriptionId: subscriptionId
            )
        )
    }

    // MARK: - Dispatch Action

    /// Accessibility 노드에 액션을 수행하도록 요청한다.
    /// - Parameters:
    ///   - targetNodeId: 대상 노드의 UUID.
    ///   - actionType: 실행할 액션. 서버 구현은 현재 `.activate`만 지원.
    ///   - value: 필요 시 액션에 동반되는 값.
    ///   - args: 추가 인자 맵.
    func dispatchAction(
        targetNodeId: UUID,
        actionType: AccessibilityActionType = .activate,
        value: AccessibilityNodeValue? = nil,
        args: [String: String] = [:]
    ) async throws -> DispatchActionResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .dispatchActionRequest,
            message: DispatchActionRequest(
                requestId: requestID,
                targetNodeId: targetNodeId,
                actionType: actionType,
                value: value,
                args: args
            )
        )
    }
}
