//
//  DiagPrinter.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/15/26.
//

import Foundation

import Darwin

import SiriusKit

enum DiagLevel {
    /// 공개용 (GitHub 이슈 등). PII 최소화.
    case simple
    /// 개발자 전달용. PII 포함 가능.
    case detailed
}

@MainActor
final class DiagPrinter: Sendable {
    func generate(level: DiagLevel) async -> String {
        var lines: [String] = []

        lines.append("=== Noctiluca Server Diagnostics ===")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Level: \(level == .simple ? "Simple" : "Detailed")")
        lines.append("")

        appendAppInfo(&lines)
        appendSystemInfo(&lines, level: level)
        await appendServerInfo(&lines, level: level)
        appendDisplayInfo(&lines, level: level)
        await appendPermissionInfo(&lines)
        appendTelemetryInfo(&lines)
        await appendPluginInfo(&lines, level: level)

        if level == .detailed {
            appendNetworkInfo(&lines)
        }

        lines.append("=== End of Diagnostics ===")
        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    private func appendAppInfo(_ lines: inout [String]) {
        lines.append("--- App ---")
        lines.append("Product: \(NoctilucaMeta.productName)")
        lines.append("Version: \(NoctilucaMeta.version) (\(NoctilucaMeta.buildVersion))")
        lines.append("Bundle ID: \(NoctilucaMeta.bundleIdentifier)")
        lines.append("")
    }

    private func appendSystemInfo(_ lines: inout [String], level: DiagLevel) {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("--- System ---")
        lines.append("macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

        if let buildVersion = macOSBuildVersion() {
            lines.append("Build: \(buildVersion)")
        }

        lines.append("Model: \(hardwareModel())")

        #if arch(arm64)
        lines.append("Architecture: arm64")
        #elseif arch(x86_64)
        lines.append("Architecture: x86_64")
        #else
        lines.append("Architecture: unknown")
        #endif

        lines.append("Virtual Machine: \(SystemCapability.isVirtualMachine ? "Yes" : "No")")

        if level == .detailed {
            lines.append("Hostname: \(hostname())")
        }

        lines.append("")
    }

    @MainActor
    private func appendServerInfo(_ lines: inout [String], level: DiagLevel) async {
        let server = NoctilucaServer.shared
        let settings = SettingsStore.shared.settings!

        lines.append("--- Server ---")

        switch server.state {
        case .idle:
            lines.append("State: Idle")
        case .preparing:
            lines.append("State: Preparing")
        case .running:
            lines.append("State: Running")
        }

        lines.append("Transport: \(settings.transport.implementation)")

        if level == .detailed {
            lines.append("Listen Port: \(settings.quicTransport.listenPort)")
            lines.append("Active Sessions: \(server.clients.count)")
            lines.append("Max Sessions: \(settings.general.maxConcurrentSessions)")
        }

        lines.append("")
    }

    @MainActor
    private func appendDisplayInfo(_ lines: inout [String], level: DiagLevel) {
        let layouts = DisplayLayoutManager.shared.displayLayouts.snapshot()

        lines.append("--- Displays ---")
        lines.append("Count: \(layouts.count)")

        for (displayID, screen) in layouts {
            var displayLine = "  - \(Int(screen.displayResolution.width))x\(Int(screen.displayResolution.height)) @\(screen.scaleFactor)x"
            if level == .detailed {
                displayLine += " (ID: \(displayID))"
            }
            lines.append(displayLine)
        }

        lines.append("")
    }

    private func appendPermissionInfo(_ lines: inout [String]) async {
        await TCCUtil.shared.refresh()
        let scopes = TCCUtil.shared.grantedScopes

        lines.append("--- Permissions ---")
        lines.append("Screen Capture: \(scopes.contains(.screenCapture) ? "Granted" : "Not Granted")")
        lines.append("Accessibility: \(scopes.contains(.accessibility) ? "Granted" : "Not Granted")")
        lines.append("Notifications: \(scopes.contains(.notifications) ? "Granted" : "Not Granted")")
        lines.append("")
    }

    @MainActor
    private func appendTelemetryInfo(_ lines: inout [String]) {
        let settings = SettingsStore.shared.settings!

        lines.append("--- Telemetry ---")
        lines.append("Available: \(TelemetryService.shared.isAvailable ? "Yes" : "No (EEA/UK)")")
        lines.append("Enabled: \(settings.telemetry.enableTelemetry ? "Yes" : "No")")
        lines.append("")
    }

    private func appendPluginInfo(_ lines: inout [String], level: DiagLevel) async {
        let bundles = await PluginBundleRegistry.shared.bundles

        lines.append("--- Plugins ---")
        lines.append("Count: \(bundles.count)")

        for (bundleID, handle) in bundles {
            let displayName = handle.manifest.name.getString()
            if level == .detailed {
                let pluginKitVersion = String(format: "0x%08X", handle.manifest.pluginKitVersion.rawValue)
                lines.append("  - \(displayName) (\(bundleID)) PluginKit=\(pluginKitVersion)")
                if let signingResult = handle.signingResult {
                    lines.append("    Signing: \(signingResult)")
                }
            } else {
                lines.append("  - \(displayName)")
            }
        }

        lines.append("")
    }

    private func appendNetworkInfo(_ lines: inout [String]) {
        lines.append("--- Network Interfaces ---")

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            lines.append("  (unavailable)")
            lines.append("")
            return
        }

        defer { freeifaddrs(firstAddr) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            let name = String(cString: addr.pointee.ifa_name)
            if let sockaddr = addr.pointee.ifa_addr {
                let family = sockaddr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(sockaddr, socklen_t(MemoryLayout<sockaddr_in>.size),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    lines.append("  - \(name): \(String(cString: hostname))")
                } else if family == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(sockaddr, socklen_t(MemoryLayout<sockaddr_in6>.size),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    lines.append("  - \(name): \(String(cString: hostname))")
                }
            }
            current = addr.pointee.ifa_next
        }

        lines.append("")
    }

    // MARK: - Helpers

    private func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    private func macOSBuildVersion() -> String? {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var version = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &version, &size, nil, 0)
        return String(cString: version)
    }
}
