//
//  SiriusFileLogDestination.swift
//  SiriusKit
//

import Foundation

public final class SiriusFileLogDestination: SiriusLogDestination {

    /// Rotation configuration. When provided, log files rotate on size threshold.
    public struct RotationPolicy: Sendable {
        /// Maximum size of a single log file in bytes. Rotation triggers when exceeded.
        public let maxFileSize: UInt64
        /// Maximum number of files to keep (including the current file).
        /// Oldest files are deleted when this limit is exceeded.
        public let maxFileCount: Int

        public init(maxFileSize: UInt64, maxFileCount: Int) {
            self.maxFileSize = maxFileSize
            self.maxFileCount = max(maxFileCount, 1)
        }
    }

    private let fileURL: URL
    private let rotationPolicy: RotationPolicy?
    private let includeMetadata: Bool
    private let queue: DispatchQueue
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64

    /// Creates a file log destination without rotation.
    public init(fileURL: URL, includeMetadata: Bool = true) {
        self.fileURL = fileURL
        self.rotationPolicy = nil
        self.includeMetadata = includeMetadata
        self.queue = DispatchQueue(label: "so.libsirius.SiriusKit.logger.file.\(fileURL.lastPathComponent)")
        self.currentFileSize = 0
        self.fileHandle = nil
        openOrCreateFile()
    }

    /// Creates a file log destination with rotation.
    public init(fileURL: URL, rotationPolicy: RotationPolicy, includeMetadata: Bool = true) {
        self.fileURL = fileURL
        self.rotationPolicy = rotationPolicy
        self.includeMetadata = includeMetadata
        self.queue = DispatchQueue(label: "so.libsirius.SiriusKit.logger.file.\(fileURL.lastPathComponent)")
        self.currentFileSize = 0
        self.fileHandle = nil
        openOrCreateFile()
    }

    deinit {
        fileHandle?.closeFile()
    }

    // MARK: - SiriusLogDestination

    public func write(
        level: SiriusLogLevel,
        subsystem: String,
        category: String,
        message: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level != .off else { return }

        let formatted: String
        if includeMetadata {
            formatted = "[\(SiriusLogTimestamp.now())][\(subsystem)][\(category):\(level.label)][\(file):\(line)][\(function)] \(message)\n"
        } else {
            formatted = "\(message)\n"
        }

        guard let data = formatted.data(using: .utf8) else { return }

        queue.sync {
            if let policy = rotationPolicy, currentFileSize + UInt64(data.count) > policy.maxFileSize {
                rotateFiles()
            }

            fileHandle?.write(data)
            currentFileSize += UInt64(data.count)
        }
    }

    // MARK: - Private

    private func openOrCreateFile() {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()

        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
        currentFileSize = fileHandle?.offsetInFile ?? 0
    }

    private func rotateFiles() {
        fileHandle?.closeFile()
        fileHandle = nil

        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        let directory = fileURL.deletingLastPathComponent()

        let maxIndex = (rotationPolicy?.maxFileCount ?? 1) - 1

        // Delete the oldest file if it exists
        let oldestURL = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: maxIndex)
        try? FileManager.default.removeItem(at: oldestURL)

        // Shift existing rotated files by incrementing their index
        for i in stride(from: maxIndex - 1, through: 1, by: -1) {
            let src = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: i)
            let dst = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: i + 1)
            try? FileManager.default.moveItem(at: src, to: dst)
        }

        // Move current file to .1
        let firstRotated = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: 1)
        try? FileManager.default.moveItem(at: fileURL, to: firstRotated)

        openOrCreateFile()
    }

    private func rotatedFileURL(directory: URL, baseName: String, ext: String, index: Int) -> URL {
        if ext.isEmpty {
            return directory.appendingPathComponent("\(baseName).\(index)")
        } else {
            return directory.appendingPathComponent("\(baseName).\(index).\(ext)")
        }
    }
}
