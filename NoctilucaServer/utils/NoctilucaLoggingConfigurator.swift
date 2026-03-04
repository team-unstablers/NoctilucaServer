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
        // SiriusLogger: OSLog만 사용 (파일 destination 제거)
        SiriusLogger.resetDestinationBuilder()

        // SiriusEventLogger: 설정에 따라 파일 destination 추가
        if settings.enableFileLogging {
            let fileDestination: SiriusEventFileLogDestination
            if settings.enableLogRotation {
                fileDestination = SiriusEventFileLogDestination(
                    fileURL: logFileURL,
                    rotationPolicy: .init(
                        maxFileSize: settings.maxFileSize,
                        maxFileCount: settings.maxFileCount
                    )
                )
            } else {
                fileDestination = SiriusEventFileLogDestination(fileURL: logFileURL)
            }

            SiriusEventLogger.configure(destinationBuilder: {
                var destinations: [any SiriusEventLogDestination] = []
                if #available(macOS 11.0, *) {
                    destinations.append(SiriusOSEventLogDestination())
                }
                destinations.append(fileDestination)
                return destinations
            })
        } else {
            SiriusEventLogger.configure(destinationBuilder: nil)
        }
    }
}
