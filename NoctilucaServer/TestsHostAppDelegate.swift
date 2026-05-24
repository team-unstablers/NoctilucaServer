//
//  AppDelegate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import AppKit
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        
        // ignore SIGPIPE to prevent app from crashing when trying to write to a closed socket
        signal(SIGPIPE, SIG_IGN);

        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
    }


    @objc
    func showOnboardingWindow(_ sender: Any?) {
    }

    @objc
    func showSettingsWindow(_ sender: Any?) {
    }

    @objc
    func startServer(_ sender: Any?) {
    }

    @objc
    func stopServer(_ sender: Any?) {
    }
}

