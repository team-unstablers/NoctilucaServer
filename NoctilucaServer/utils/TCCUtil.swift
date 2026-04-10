//
//  TCCUtil.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Cocoa
@preconcurrency import ApplicationServices
import UserNotifications
import CoreGraphics

import SiriusKitCore

enum TCCScope {
    case accessibility
    case screenCapture
    case notifications
}

class TCCUtil: @unchecked Sendable {
    public static let shared = TCCUtil()
    
    private let logger = NoctilucaLogger(category: "TCCUtil")
    private(set) public var grantedScopes: Set<TCCScope> = []
    
    func refresh() async {
        grantedScopes = []
        
        if AXIsProcessTrusted() {
            grantedScopes.insert(.accessibility)
        }
        
        if CGPreflightScreenCaptureAccess() {
            grantedScopes.insert(.screenCapture)
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
            CGRequestScreenCaptureAccess()
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
    
    /// 자기 자신을 재기동합니다
    func relaunchApp() -> Bool {
        let appURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        
        let script = """
        while kill -0 \(pid) 2>/dev/null; do 
            sleep 1
        done
        
        open "\(appURL.path)"
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        
        do {
            try process.run()
            
            exit(0)
            
            return true
        } catch {
            logger.error("Failed to relaunch app: \(error)")
        }
        
        return false
    }
}
