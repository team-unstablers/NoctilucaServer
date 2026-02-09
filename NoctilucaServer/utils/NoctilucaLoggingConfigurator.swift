//
//  NoctilucaLoggingConfigurator.swift
//  NoctilucaServer
//

import Foundation
import SiriusKit

enum NoctilucaLoggingConfigurator {
    /// ~/Library/Logs/app.noctiluca.server/
    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
            .appendingPathComponent(NoctilucaMeta.bundleIdentifier)
    }

    /// ~/Library/Logs/app.noctiluca.server/noctiluca.log
    static var logFileURL: URL {
        logDirectory.appendingPathComponent("noctiluca.log")
    }

    static func apply(settings: AppSettings.Logging) {
        let level = SiriusLogLevel.from(label: settings.minimumLogLevel) ?? .trace

        if settings.enableFileLogging {
            let fileDestination: SiriusFileLogDestination
            if settings.enableLogRotation {
                fileDestination = SiriusFileLogDestination(
                    fileURL: logFileURL,
                    rotationPolicy: .init(
                        maxFileSize: settings.maxFileSize,
                        maxFileCount: settings.maxFileCount
                    )
                )
            } else {
                fileDestination = SiriusFileLogDestination(fileURL: logFileURL)
            }

            SiriusLogger.configure(minimumLevel: level, destinationBuilder: { subsystem, category in
                var destinations: [any SiriusLogDestination] = []
                if #available(macOS 11.0, *) {
                    destinations.append(SiriusOSLogDestination(subsystem: subsystem, category: category))
                }
                destinations.append(fileDestination)
                return destinations
            })
        } else {
            SiriusLogger.resetDestinationBuilder()
            SiriusLogger.configure(minimumLevel: level)
        }
    }
}
