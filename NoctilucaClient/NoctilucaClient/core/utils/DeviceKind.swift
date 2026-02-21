//
//  UIDevice+isTablet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/20/25.
//

#if canImport(UIKit)
import UIKit
#endif

enum DeviceKind {
    case iPad
    case iPhone
    case mac
    
    static var current: DeviceKind {
#if os(macOS)
        return .mac
#elseif canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPad
        } else {
            return .iPhone
        }
#else
        return .mac
#endif
    }
}

extension DeviceKind: CustomStringConvertible {
    var description: String {
        switch self {
        case .iPad:
            return "iPad"
        case .iPhone:
            return "iPhone"
        case .mac:
            return "Mac"
        }
    }
    
    var osDescription: String {
        switch self {
        case .iPad:
            return "iPadOS"
        case .iPhone:
            return "iOS"
        case .mac:
            return "macOS"
        }
    }
}
