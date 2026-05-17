//
//  main.swift
//  NoctilucaPluginKitHost
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import AppKit
import Logging
import Shotoku
import NoctilucaPluginKitHostCore

@MainActor
final class HostAppDelegate: NSObject, NSApplicationDelegate {

    private var listener: RPCListener<HostControlInterfaceImpl>?
    private let logger = Logger(label: "app.noctiluca.server.plugin-host")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let service = HostControlInterfaceImpl()
                let listener = RPCListener<HostControlInterfaceImpl>(
                    service,
                    endpoint: .xpc("app.noctiluca.server.NoctilucaPluginKitHost"),
                    logger: self.logger
                )
                self.listener = listener
                try await listener.start()
                self.logger.info("Plugin host listener started")
            } catch {
                self.logger.error("Plugin host listener failed to start: \(error)")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let listener {
            Task {
                await listener.stop()
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = HostAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
