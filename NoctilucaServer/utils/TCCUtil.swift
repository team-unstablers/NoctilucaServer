//
//  TCCUtil.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Cocoa
import ApplicationServices
import UserNotifications

enum TCCScope {
    case accessibility
    case screenCapture
    case notifications
}

class TCCUtil {
    public static let shared = TCCUtil()
    
    private(set) public var grantedScopes: Set<TCCScope> = []
    
    func refresh() async {
        grantedScopes = []
        
        if AXIsProcessTrusted() {
            grantedScopes.insert(.accessibility)
        }
        
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            grantedScopes.insert(.notifications)
        default:
            break
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
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }
    
    func openSystemPreferences(for scope: TCCScope) {
        var urlString: String
        
        switch scope {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenCapture:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
