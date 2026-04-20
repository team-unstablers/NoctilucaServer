//
//  ProjectionChannel+winman.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation
import SiriusKit

import AppKit
import CoreGraphics


extension ProjectionChannel {

    // MARK: - Window Query Handlers

    func handleWindowListRequest(_ request: WindowListRequest) async throws {
        var windowList = await desktopContextManager.globalWindowList()

        if let filter = request.filter {
            windowList = windowList.filter { filter.matches($0) }
        }
        
        // TODO: support paginated response
        let response = WindowListResponse(
            requestID: request.requestID,
            windows: windowList,
            isLastPage: true
        )

        try await self.handle.send(opcode: .windowListResponse, message: response)
    }

    func handleGetWindowInfoRequest(_ request: GetWindowInfoRequest) async throws {
        let windowList = await desktopContextManager.globalWindowList()
        let info = windowList.first(where: { $0.windowID == request.windowID })

        let response = GetWindowInfoResponse(
            requestID: request.requestID,
            info: info
        )
        try await self.handle.send(opcode: .getWindowInfoResponse, message: response)
    }

    func handleGetWindowIconRequest(_ request: GetWindowIconRequest) async throws {
        let app = await desktopContextManager.findRunningApplication(forWindowID: WindowID(request.windowID))
        let iconData: Data? = app?.icon?.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
        }

        let response = GetWindowIconResponse(
            requestID: request.requestID,
            windowID: request.windowID,
            icon: iconData
        )
        try await self.handle.send(opcode: .getWindowIconResponse, message: response)
    }

    func handleGetWindowThumbnailRequest(_ request: GetWindowThumbnailRequest) async throws {
        // TODO: ScreenCaptureKit 기반 윈도우 썸네일 캡처 구현
        let response = GetWindowThumbnailResponse(
            requestID: request.requestID,
            windowID: request.windowID,
            thumbnail: nil
        )
        try await self.handle.send(opcode: .getWindowThumbnailResponse, message: response)
    }

    // MARK: - Window Event Subscription Handlers

    func handleSubscribeWindowEventsRequest(_ request: SubscribeWindowEventsRequest) async throws {
        let subscriptionID = await desktopContextManager.subscribeWindowEvents(
            eventMask: request.eventMask,
            filter: request.filter,
            flags: request.flags
        ) { [weak self] event in
            Task { [weak self] in
                try? await self?.handle.send(opcode: .windowChangedEvent, message: event)
            }
        }

        let response = SubscribeWindowEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscriptionID
        )
        try await self.handle.send(opcode: .subscribeWindowEventsResponse, message: response)
    }

    func handleUnsubscribeWindowEventsRequest(_ request: UnsubscribeWindowEventsRequest) async throws {
        let success = await desktopContextManager.unsubscribeWindowEvents(id: request.subscriptionID)

        let response = UnsubscribeWindowEventsResponse(
            requestID: request.requestID,
            subscriptionID: request.subscriptionID,
            isSuccess: success
        )
        try await self.handle.send(opcode: .unsubscribeWindowEventsResponse, message: response)
    }

    // MARK: - Window Manipulation Handlers

    func handleWindowManipulationRequest(_ request: WindowManipulationRequest) async throws {
        let windowID = WindowID(request.windowID)

        do {
            switch request.operation {
            case .stateCommand(let command):
                try await desktopContextManager.sendStateCommand(id: windowID, command: command)
            case .focus(let focused):
                if focused {
                    try await desktopContextManager.focusWindow(id: windowID)
                }
            case .setGeometry(let rect):
                // AppStream 대상 윈도우는 가상 디스플레이의 origin에 anchor되어야 하므로
                // 클라이언트가 보내는 position은 무시하고 size만 반영한다. (anchor와의 ping-pong 방지)
                let frameToApply = await resolveSetGeometryFrame(windowID: windowID, requested: rect.cgRect)
                try await desktopContextManager.setWindowFrame(
                    id: windowID,
                    frame: frameToApply
                )
            case .setFlags(_), .clearFlags(_):
                break // macOS에서는 flags 직접 조작 미지원
            }

            let response = WindowManipulationResponse(
                isSuccess: true,
                code: 0,
                message: nil
            )
            try await self.handle.send(opcode: .windowManipulationResponse, message: response)
        } catch {
            let response = WindowManipulationResponse(
                isSuccess: false,
                code: 1,
                message: error.localizedDescription
            )
            try await self.handle.send(opcode: .windowManipulationResponse, message: response)
        }
    }

    /// setGeometry 적용 frame을 결정한다.
    /// - AppStream 세션 대상 윈도우(같은 PID): position 무시, size만 반영 — 현재 origin 유지
    /// - 그 외: 요청 그대로 적용
    private func resolveSetGeometryFrame(windowID: WindowID, requested: CGRect) async -> CGRect {
        guard let appStreamSession = await state.currentAppStreamSession() else {
            return requested
        }
        guard let info = await desktopContextManager.windowInfo(for: windowID),
              pid_t(info.pid) == appStreamSession.pid
        else {
            return requested
        }
        let currentOrigin = CGPoint(x: info.bounds.x, y: info.bounds.y)
        return CGRect(origin: currentOrigin, size: requested.size)
    }
}
