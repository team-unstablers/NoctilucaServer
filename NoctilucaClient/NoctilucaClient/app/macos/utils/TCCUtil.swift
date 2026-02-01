//
//  TCCUtil.swift
//  NoctilucaClient
//
//  Created by Codex on 12/21/25.
//

#if os(macOS)

import Foundation
import Cocoa
import ApplicationServices

enum TCCScope {
    case accessibility
    case screenCapture
    case inputMonitoring
}

class TCCUtil {
    public static let shared = TCCUtil()

    func isAccessGranted(for scope: TCCScope) -> Bool {
        switch scope {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenCapture:
            return CGPreflightScreenCaptureAccess()
        case .inputMonitoring:
            return CGPreflightListenEventAccess()
        }
    }

    func requestAccess(for scope: TCCScope) {
        switch scope {
        case .accessibility:
            let options: [String: Bool] = [
                kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
            ]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        case .screenCapture:
            _ = CGRequestScreenCaptureAccess()
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
    }

    func openSystemPreferences(for scope: TCCScope) {
        let urlString: String

        switch scope {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenCapture:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

#endif
