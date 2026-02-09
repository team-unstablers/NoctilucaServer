//
//  SiriusFileLogDestinationTests.swift
//  SiriusKitTests
//

import Foundation
import Testing

@testable import SiriusKit

@Suite("SiriusFileLogDestination")
struct SiriusFileLogDestinationTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiriusLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("writes message to file")
    func writesMessageToFile() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")

        let dest = SiriusFileLogDestination(fileURL: fileURL, includeMetadata: false)
        dest.write(level: .info, subsystem: "test", category: "cat", message: "hello world",
                   file: "f", function: "fn", line: 1)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content == "hello world\n")
    }

    @Test("writes with metadata when includeMetadata is true")
    func writesWithMetadata() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")

        let dest = SiriusFileLogDestination(fileURL: fileURL, includeMetadata: true)
        dest.write(level: .warning, subsystem: "sub", category: "cat", message: "warn msg",
                   file: "File.swift", function: "doStuff()", line: 42)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("[sub]"))
        #expect(content.contains("[cat:WARNING]"))
        #expect(content.contains("[File.swift:42]"))
        #expect(content.contains("[doStuff()]"))
        #expect(content.contains("warn msg"))
    }

    @Test("does not write when level is .off")
    func doesNotWriteForOff() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")

        let dest = SiriusFileLogDestination(fileURL: fileURL, includeMetadata: false)
        dest.write(level: .off, subsystem: "test", category: "cat", message: "nope",
                   file: "f", function: "fn", line: 1)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.isEmpty)
    }

    @Test("creates file if not exists")
    func createsFileIfNotExists() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("subdir/nested.log")

        let dest = SiriusFileLogDestination(fileURL: fileURL, includeMetadata: false)
        dest.write(level: .info, subsystem: "test", category: "cat", message: "created",
                   file: "f", function: "fn", line: 1)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content == "created\n")
    }

    @Test("appends to existing file")
    func appendsToExistingFile() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")
        try "existing\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let dest = SiriusFileLogDestination(fileURL: fileURL, includeMetadata: false)
        dest.write(level: .info, subsystem: "test", category: "cat", message: "appended",
                   file: "f", function: "fn", line: 1)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content == "existing\nappended\n")
    }

    @Test("rotation triggers when file exceeds maxFileSize")
    func rotationTriggersOnSize() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")

        let policy = SiriusFileLogDestination.RotationPolicy(maxFileSize: 50, maxFileCount: 3)
        let dest = SiriusFileLogDestination(fileURL: fileURL, rotationPolicy: policy, includeMetadata: false)

        // Write enough to trigger rotation (each write ~11 bytes: "message ##\n")
        for i in 0..<10 {
            dest.write(level: .info, subsystem: "s", category: "c", message: "message \(String(format: "%02d", i))",
                       file: "f", function: "fn", line: 1)
        }

        // Check that rotated files exist
        let rotated1 = dir.appendingPathComponent("test.1.log")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: rotated1.path))
    }

    @Test("rotation respects maxFileCount and deletes oldest")
    func rotationRespectsMaxFileCount() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")

        // Very small maxFileSize to trigger rotation frequently, keep max 2 files
        let policy = SiriusFileLogDestination.RotationPolicy(maxFileSize: 20, maxFileCount: 2)
        let dest = SiriusFileLogDestination(fileURL: fileURL, rotationPolicy: policy, includeMetadata: false)

        // Write many messages to trigger multiple rotations
        for i in 0..<20 {
            dest.write(level: .info, subsystem: "s", category: "c", message: "msg-\(String(format: "%02d", i))",
                       file: "f", function: "fn", line: 1)
        }

        // maxFileCount=2 means current file + 1 rotated file max
        let rotated1 = dir.appendingPathComponent("test.1.log")
        let rotated2 = dir.appendingPathComponent("test.2.log")

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: rotated1.path))
        #expect(!FileManager.default.fileExists(atPath: rotated2.path))
    }

    @Test("no rotation in single file mode")
    func noRotationInSingleFileMode() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("test.log")

        let dest = SiriusFileLogDestination(fileURL: fileURL, includeMetadata: false)

        for i in 0..<50 {
            dest.write(level: .info, subsystem: "s", category: "c", message: "line \(i)",
                       file: "f", function: "fn", line: 1)
        }

        // No rotated files should exist
        let rotated1 = dir.appendingPathComponent("test.1.log")
        #expect(!FileManager.default.fileExists(atPath: rotated1.path))
    }

    @Test("handles file without extension in rotation naming")
    func handlesNoExtension() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("logfile")

        let policy = SiriusFileLogDestination.RotationPolicy(maxFileSize: 30, maxFileCount: 3)
        let dest = SiriusFileLogDestination(fileURL: fileURL, rotationPolicy: policy, includeMetadata: false)

        for i in 0..<10 {
            dest.write(level: .info, subsystem: "s", category: "c", message: "msg-\(String(format: "%02d", i))",
                       file: "f", function: "fn", line: 1)
        }

        // Without extension, rotated file should be "logfile.1" (not "logfile.1.")
        let rotated1 = dir.appendingPathComponent("logfile.1")
        #expect(FileManager.default.fileExists(atPath: rotated1.path))
    }
}
