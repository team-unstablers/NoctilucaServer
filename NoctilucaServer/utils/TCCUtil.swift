//
//  TCCUtil.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Cocoa
import ApplicationServices

enum TCCScope {
    case accessibility
    case screenCapture
}

class TCCUtil {
    public static let shared = TCCUtil()
    
    private(set) public var grantedScopes: Set<TCCScope> = []
    
    func refresh() {
        grantedScopes = []
        
        if AXIsProcessTrusted() {
            grantedScopes.insert(.accessibility)
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
            // No API to request screen capture permission programmatically.
            break
        }
    }
    
    func openSystemPreferences(for scope: TCCScope) {
        var urlString: String
        
        switch scope {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenCapture:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
