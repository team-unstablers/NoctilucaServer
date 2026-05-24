//
//  ProjectionChannel+winman.swift
//  NoctilucaClient
//
//  Created by Claude on 2/23/26.
//

import Foundation
import SiriusKitClient

// MARK: - Window Manager Request/Response

extension ProjectionChannel {

    // MARK: Window Query

    func requestWindowList(
        filter: WindowFilter? = nil,
        flags: WindowListRequestFlagSet = .none
    ) async throws -> WindowListResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .windowListRequest,
            message: WindowListRequest(
                requestID: requestID,
                filter: filter,
                flags: flags
            )
        )
    }

    func requestWindowInfo(windowID: UInt64) async throws -> GetWindowInfoResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .getWindowInfoRequest,
            message: GetWindowInfoRequest(
                requestID: requestID,
                windowID: windowID
            )
        )
    }

    func requestWindowIcon(windowID: UInt64) async throws -> GetWindowIconResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .getWindowIconRequest,
            message: GetWindowIconRequest(
                requestID: requestID,
                windowID: windowID
            )
        )
    }

    func requestWindowThumbnail(windowID: UInt64) async throws -> GetWindowThumbnailResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .getWindowThumbnailRequest,
            message: GetWindowThumbnailRequest(
                requestID: requestID,
                windowID: windowID
            )
        )
    }

    // MARK: Window Event Subscription

    func subscribeWindowEvents(
        eventMask: WindowChangeEventType,
        filter: WindowFilter? = nil,
        flags: WindowEventSubscriptionFlagSet = .none
    ) async throws -> SubscribeWindowEventsResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .subscribeWindowEventsRequest,
            message: SubscribeWindowEventsRequest(
                requestID: requestID,
                eventMask: eventMask,
                filter: filter,
                flags: flags
            )
        )
    }

    func unsubscribeWindowEvents(subscriptionID: UUID) async throws -> UnsubscribeWindowEventsResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .unsubscribeWindowEventsRequest,
            message: UnsubscribeWindowEventsRequest(
                requestID: requestID,
                subscriptionID: subscriptionID
            )
        )
    }

    // MARK: Window Manipulation

    func requestWindowManipulation(
        windowID: UInt64,
        operation: WindowManipulationRequest.Operation,
        extraArgs: [String: String] = [:],
        flags: UInt32 = 0
    ) async throws -> WindowManipulationResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .windowManipulationRequest,
            message: WindowManipulationRequest(
                windowID: windowID,
                operation: operation,
                extraArgs: extraArgs,
                flags: flags
            )
        )
    }

    // MARK: Event Handlers

    func handleWindowChangedEvent(_ event: WindowChangedEvent) async {
        // TODO: implement
    }
}
