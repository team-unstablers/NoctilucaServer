//
//  ProjectionChannel+displayman.swift
//  NoctilucaClient
//
//  Created by Codex on 1/28/26.
//

import Foundation
import Combine
import SiriusKitClient

// MARK: - Displayman Request/Response

extension ProjectionChannel {

    /// DisplayListRequest를 전송하고 응답을 기다립니다.
    func requestDisplayList() async throws -> DisplayListResponse {
        let requestID = nextRequestID()

        try await self.send(opcode: .displayListRequest, message: DisplayListRequest(
            requestID: requestID,
            flags: 0
        ))

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingDisplayListRequests[requestID] = { response in
                continuation.resume(returning: response)
            }
        }
    }

    /// 서버로부터 디스플레이 변경 이벤트를 구독합니다.
    func subscribeDisplayChanges(eventMask: DisplayChangeEventType = []) async throws -> SubscribeDisplayChangesResponse {
        let requestID = nextRequestID()

        try await self.send(opcode: .subscribeDisplayChangesRequest, message: SubscribeDisplayChangesRequest(
            requestID: requestID,
            eventMask: eventMask,
            flags: 0
        ))

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingSubscribeDisplayChangesRequests[requestID] = { response in
                continuation.resume(returning: response)
            }
        }
    }

    /// 디스플레이 변경 이벤트 구독을 해제합니다.
    func unsubscribeDisplayChanges() async throws {
        guard let subscriptionID = self.displayChangesSubscriptionID else {
            return
        }

        let requestID = nextRequestID()

        try await self.send(opcode: .unsubscribeDisplayChangesRequest, message: UnsubscribeDisplayChangesRequest(
            requestID: requestID,
            subscriptionID: subscriptionID
        ))

        self.displayChangesSubscriptionID = nil
    }

    /// DisplayChangedEvent를 처리합니다. 디바운스 Subject로 전달합니다.
    func handleDisplayChangedEvent(_ event: DisplayChangedEvent) {
        self.logger.info("Received DisplayChangedEvent: eventType=\(event.eventType.rawValue), displayID=\(event.display.displayID)")
        self.displayChangeSubject.send(event)
    }
}

// MARK: - Internal Displayman Response Handlers

extension ProjectionChannel {

    func handleDisplayListResponse(_ response: DisplayListResponse) {
        if let continuation = self.pendingDisplayListRequests[response.requestID] {
            self.pendingDisplayListRequests.removeValue(forKey: response.requestID)
            continuation(response)
        } else {
            self.logger.warning("No pending DisplayListRequest found for requestID: \(response.requestID)")
        }
    }

    func handleSubscribeDisplayChangesResponse(_ response: SubscribeDisplayChangesResponse) {
        if let continuation = self.pendingSubscribeDisplayChangesRequests[response.requestID] {
            self.pendingSubscribeDisplayChangesRequests.removeValue(forKey: response.requestID)
            self.displayChangesSubscriptionID = response.subscriptionID
            continuation(response)
        } else {
            self.logger.warning("No pending SubscribeDisplayChangesRequest found for requestID: \(response.requestID)")
        }
    }
}
