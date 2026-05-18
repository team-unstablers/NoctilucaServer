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
        let pid = ProcessInfo.processInfo.processIdentifier
        self.logger.info("Plugin host process launched (pid=\(pid))")
        Task { [weak self] in
            guard let self else { return }
            do {
                let service = HostControlInterfaceImpl()

                // docs/xpc-safety.md §3.1 — listener-side double gate.
                //   1) libxpc OS-level: `peerCodeSigningRequirement` 으로
                //      connection 단계에서 server 본체 DR 매칭.
                //   2) app-level: `authorize:` 클로저가
                //      `XPCPeerIdentity.verify(...)` 로 audit token 을 다시
                //      평가. 연결 거부 시 한 줄 로그 (§3.8 의 최소 관찰성).
                let endpointOptions = RPCXPCEndpointOptions(
                    peerCodeSigningRequirement: XPCPeerIdentity.serverPeerRequirement
                )
                let listenerLogger = self.logger
                let listener = RPCListener<HostControlInterfaceImpl>(
                    service,
                    endpoint: .xpc(
                        "app.noctiluca.server.NoctilucaPluginKitHost",
                        options: endpointOptions
                    ),
                    authorize: { context in
                        Self.authorizePeer(context: context, logger: listenerLogger)
                    },
                    logger: listenerLogger
                )
                self.listener = listener
                try await listener.start()
                self.logger.info("Plugin host listener started (pid=\(pid))")
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

    /// `RPCListener` 의 `authorize:` 클로저 본체. connection-level / message-
    /// level 양쪽에서 호출되며, peer 가 `XPCPeerIdentity.serverPeerRequirement`
    /// 를 만족하지 못하면 false 를 반환해 호출을 거부한다.
    ///
    /// `RPCAuthorizationPolicy` 기본값 `[.connection, .message]` 와 결합되어,
    /// 연결 직후 + 매 RPC 디스패치 직전에 audit token 이 다시 평가된다.
    private static func authorizePeer(
        context: RPCCallContext,
        logger: Logger
    ) -> Bool {
        guard let process = context.peer.process else {
            // InProcess transport — XPC 경계가 없으니 검증 대상이 아님.
            // 현 host 는 XPC endpoint 만 listen 하므로 실제로는 이 경로가
            // 도달하지 않지만, 안전한 기본값으로 reject.
            logger.warning(
                "XPC authorize: rejecting peer with no process info (procedure=\(context.procedure))"
            )
            return false
        }

        let result = XPCPeerIdentity.verify(
            auditToken: process.auditToken,
            designatedRequirement: XPCPeerIdentity.serverPeerRequirement
        )

        switch result {
        case .success:
            logger.debug(
                "XPC authorize: accepted peer pid=\(process.pid) euid=\(process.euid) procedure=\(context.procedure)"
            )
            return true
        case .failure(let error):
            logger.error(
                "XPC authorize: rejected peer pid=\(process.pid) euid=\(process.euid) procedure=\(context.procedure) reason=\(error)"
            )
            return false
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
