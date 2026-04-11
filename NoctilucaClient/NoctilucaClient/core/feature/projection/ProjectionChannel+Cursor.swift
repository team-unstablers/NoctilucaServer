//
//  ProjectionChannel+cursor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/31/26.
//

import Foundation

import CoreGraphics

import SiriusKitClient

extension ProjectionChannel {
    // MARK: - Cursor Events
    
    func handleCursorEvent(_ event: CursorEvent) async throws {
        switch event.event {
        case .imageEvent(let imageEvent):
            try await handleCursorImageEvent(imageEvent)
        case .moveEvent(let moveEvent):
            await handleCursorMoveEvent(moveEvent)
        default:
            break
        }
    }
    
    func handleCursorMoveEvent(_ event: CursorMoveEvent) {
        self.continuation.yield(.cursorMoved(event))
    }

    func handleCursorImageEvent(_ event: CursorImageEvent) async throws {
        guard let data = event.imageData,
              CGDataProvider(data: data as CFData) != nil
        else {
            return
        }

        self.continuation.yield(.cursorImageChanged(event))
    }

    // MARK: - Cursor Event Subscription

    func subscribeCursorEvents() async throws {
        try await self.handle.send(opcode: .subscribeCursorEventsRequest, message: SubscribeCursorEventsRequest(
            // FIXME
            requestID: nextRequestID(),
            flags: []
        ))
    }

    func unsubscribeCursorEvents() async throws {
        try await self.handle.send(opcode: .unsubscribeCursorEventsRequest, message: UnsubscribeCursorEventsRequest(
            // FIXME
            requestID: nextRequestID(),
            subscriptionID: UUID()
        ))
    }
    
}
