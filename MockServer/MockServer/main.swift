//
//  main.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import ArgumentParser

@available(macOS 10.15, *)
struct MockServerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "MockServer",
        abstract: "A mock Sirius server that streams video files for testing."
    )

    @Option(name: .long, help: "Path to a video file (e.g., MP4) to stream as projection source.")
    var projectionSource: String

    @Option(name: .long, help: "QUIC listening port.")
    var port: UInt16

    mutating func run() throws {
        let url = URL(fileURLWithPath: projectionSource)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(projectionSource)")
        }

        let server = MockServer(projectionSource: url, port: port)
        Task {
            print("OK")
            try await server.startup()
            await server.waitForShutdown()
        }
        
        sleep(1048576)
    }
}

MockServerCLI.main()
