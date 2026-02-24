//
//  ProjectionChannel+winman.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation
import SiriusKit

import AppKit


extension ProjectionChannel {

    // MARK: - Window Query Handlers

    func handleWindowListRequest(_ request: WindowListRequest) async throws {
        let windowList = await desktopContextManager.globalWindowList()
        
        
        // TODO: support paginated response
        let response = WindowListResponse(
            requestID: request.requestID,
            windows: windowList,
            isLastPage: true
        )
        
        try await self.send(opcode: .windowListResponse, message: response)
    }

    func handleGetWindowInfoRequest(_ request: GetWindowInfoRequest) async throws {
        // TODO: implement
    }

    func handleGetWindowIconRequest(_ request: GetWindowIconRequest) async throws {
        // TODO: implement
    }

    func handleGetWindowThumbnailRequest(_ request: GetWindowThumbnailRequest) async throws {
        // TODO: implement
    }

    // MARK: - Window Event Subscription Handlers

    func handleSubscribeWindowEventsRequest(_ request: SubscribeWindowEventsRequest) async throws {
        // TODO: implement
    }

    func handleUnsubscribeWindowEventsRequest(_ request: UnsubscribeWindowEventsRequest) async throws {
        // TODO: implement
    }

    // MARK: - Window Manipulation Handlers

    func handleWindowManipulationRequest(_ request: WindowManipulationRequest) async throws {
        guard let xcode = await desktopContextManager.runningApplications().first(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" }) else {
            return
        }
        
        
        let session = try await desktopContextManager.startMonitoring(app: xcode)
        
        switch request.operation {
        case .stateCommand(let command):
            break
        case .focus(let focused):
            if focused {
                try await session.focusWindow(id: WindowID(request.windowID))
            }
        case .setGeometry(_):
            break
        case .setFlags(_):
            break
        case .clearFlags(_):
            break
        }
        
        await desktopContextManager.stopMonitoring(pid: session.pid)
        
        // TODO: implement
    }
}
