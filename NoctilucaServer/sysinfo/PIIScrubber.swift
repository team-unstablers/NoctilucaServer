//
//  PIIScrubber.swift
//  NoctilucaServer
//
//  Allowlist-based PII scrubber for Sentry events.
//  Only explicitly allowed fields are kept; everything else is stripped.
//

import Foundation

import Sentry

enum PIIScrubber {
    // MARK: - String Scrubbing Patterns

    private static let homeDirectoryPattern = try! NSRegularExpression(
        pattern: #"/(Users|home)/[^/]+"#,
        options: []
    )

    private static let ipAddressPattern = try! NSRegularExpression(
        pattern: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#,
        options: []
    )

    private static let emailPattern = try! NSRegularExpression(
        pattern: #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#,
        options: []
    )

    // MARK: - Allowed Context Keys

    private static let allowedContextKeys: Set<String> = ["os", "device", "app"]

    private static let allowedOSFields: Set<String> = ["name", "version", "build"]
    private static let allowedDeviceFields: Set<String> = ["model", "arch", "family", "model_id"]
    private static let allowedAppFields: Set<String> = ["app_name", "app_version", "app_build", "app_identifier"]

    private static let deviceFieldsToRemove: Set<String> = ["name", "hostname", "device_name", "device_id", "boot_time"]

    // MARK: - Public API

    static func scrub(_ event: Event, telemetryIdentifier: UUID?) -> Event? {
        scrubUser(event, telemetryIdentifier: telemetryIdentifier)
        scrubExtra(event)
        scrubTags(event)
        scrubBreadcrumbs(event)
        scrubContexts(event)
        scrubExceptions(event)
        scrubThreads(event)

        return event
    }

    // MARK: - String Scrubbing

    static func scrubString(_ string: String) -> String {
        var result = string
        let range = NSRange(result.startIndex..., in: result)

        result = homeDirectoryPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "~"
        )

        let ipRange = NSRange(result.startIndex..., in: result)
        result = ipAddressPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: ipRange,
            withTemplate: "[REDACTED:IP]"
        )

        let emailRange = NSRange(result.startIndex..., in: result)
        result = emailPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: emailRange,
            withTemplate: "[REDACTED:EMAIL]"
        )

        return result
    }

    // MARK: - Field Scrubbing

    private static func scrubUser(_ event: Event, telemetryIdentifier: UUID?) {
        let user = User()
        user.userId = telemetryIdentifier?.uuidString ?? "unknown"
        // Sentry 서버의 geo-IP lookup을 방지하기 위해 더미 IP 설정
        user.ipAddress = "0.0.0.0"
        event.user = user
    }

    private static func scrubExtra(_ event: Event) {
        event.extra = nil
    }

    private static func scrubTags(_ event: Event) {
        event.tags = nil
    }

    private static func scrubBreadcrumbs(_ event: Event) {
        event.breadcrumbs = nil
    }

    private static func scrubContexts(_ event: Event) {
        guard var context = event.context else { return }

        let keysToRemove = context.keys.filter { !allowedContextKeys.contains($0) }
        for key in keysToRemove {
            context.removeValue(forKey: key)
        }

        if var device = context["device"] {
            for field in deviceFieldsToRemove {
                device.removeValue(forKey: field)
            }
            context["device"] = device
        }
        
        // remove app.device: 기기 identifier를 제거한다
        context["app"]?.removeValue(forKey: "device")

        event.context = context
    }

    private static func scrubExceptions(_ event: Event) {
        guard let exceptions = event.exceptions else { return }

        for exception in exceptions {
            if let value = exception.value {
                exception.value = scrubString(value)
            }
            if let stacktrace = exception.stacktrace {
                scrubStacktrace(stacktrace)
            }
        }
    }

    private static func scrubThreads(_ event: Event) {
        guard let threads = event.threads else { return }

        for thread in threads {
            if let stacktrace = thread.stacktrace {
                scrubStacktrace(stacktrace)
            }
        }
    }

    private static func scrubStacktrace(_ stacktrace: SentryStacktrace) {
        for frame in stacktrace.frames {
            if let fileName = frame.fileName {
                frame.fileName = scrubString(fileName)
            }
        }
    }
}
