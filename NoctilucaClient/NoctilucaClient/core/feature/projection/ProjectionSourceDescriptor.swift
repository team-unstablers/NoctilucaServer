//
//  ProjectionSourceDescriptor.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/23/26.
//

import Foundation

import SiriusKitClient

enum ProjectionSourceDescriptor: CustomDebugStringConvertible, Equatable, Hashable {
    case displayID(Int)

    @available(iOS, unavailable)
    case windowID(Int)

    var debugDescription: String {
        switch self {
        case .displayID(let displayID):
            return "Display ID #\(displayID)"
        case .windowID(let windowID):
            return "Window ID #\(windowID)"
        }
    }

    func toProjectionSource(flags: ProjectionSourceFlags = []) -> ProjectionSource {
        switch self {
        case .displayID(let id):
            return ProjectionSource(
                value: .entireDisplay(EntireDisplayProjectionSource(displayID: Int32(id))),
                flags: flags
            )
        case .windowID(let id):
            return ProjectionSource(
                value: .singleWindow(SingleWindowProjectionSource(windowID: Int64(id), flags: .followSource)),
                flags: flags
            )
        }
    }

    func toCursorPositionScope() -> CursorPositionScope {
        switch self {
        case .displayID(let id):
            return .displayId(Int32(id))
        case .windowID(let id):
            return .windowId(Int64(id))
        }
    }
}
