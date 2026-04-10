//
//  TelemetryService.swift
//  NoctilucaServer
//
//  Sentry lifecycle manager. Handles initialization, shutdown,
//  and telemetry identifier reset with EEA/UK region gating.
//

import Foundation
import OSLog

import Sentry

final class TelemetryService: @unchecked Sendable {
    static let shared = TelemetryService()

    private let logger = Logger(
        subsystem: NoctilucaMeta.bundleIdentifier,
        category: "TelemetryService"
    )

    private(set) var isRunning = false

    /// EEA/UK 기기가 아닌 경우에만 텔레메트리 활성화 가능
    var isAvailable: Bool {
        !SystemRegion.isEEAOrUK
    }

    private init() {}

    // MARK: - Lifecycle

    /// 텔레메트리를 시작한다. 호출 전에 `ensureIdentifier()`로 식별자가 준비되어 있어야 한다.
    func startIfNeeded(settings: AppSettings.Telemetry) {
        guard isAvailable else {
            logger.info("Telemetry unavailable: EEA/UK region detected.")
            return
        }

        guard settings.enableTelemetry else {
            logger.info("Telemetry disabled by user preference.")
            return
        }

        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
              !dsn.isEmpty else {
            logger.warning("Sentry DSN not found in Info.plist.")
            return
        }

        let telemetryIdentifier = settings.telemetryIdentifier

        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false

            options.releaseName = "\(NoctilucaMeta.bundleIdentifier)@\(NoctilucaMeta.version)+\(NoctilucaMeta.buildVersion)"
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif

            // Breadcrumbs: 자동 수집 비활성화
            options.enableAutoBreadcrumbTracking = false
            options.maxBreadcrumbs = 0

            // Performance: 비활성화
            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0

            options.beforeSend = { event in
                return PIIScrubber.scrub(event, telemetryIdentifier: telemetryIdentifier)
            }
        }

        isRunning = true
        logger.info("Sentry started. Telemetry identifier: \(telemetryIdentifier?.uuidString ?? "unknown", privacy: .public)")
    }

    func stop() {
        guard isRunning else { return }

        SentrySDK.flush(timeout: 5.0)
        SentrySDK.close()

        isRunning = false
        logger.info("Sentry stopped.")
    }

    // MARK: - Identifier Management

    /// 식별자를 재설정하고 Sentry를 재시작한다.
    /// 호출 전에 `settings.resetIdentifier()`가 수행되어 있어야 한다.
    func restart(settings: AppSettings.Telemetry) {
        stop()
        startIfNeeded(settings: settings)
    }
}
