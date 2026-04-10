//
//  SiriusEventFileLogDestination.swift
//  SiriusKit
//

import Foundation

/// 이벤트 로그를 파일에 기록하는 destination.
/// SiriusFileLogDestination과 동일한 버퍼링/로테이션 로직을 사용한다.
// FIXME: 시간이 없어 @unchecked Sendable로 마킹. 
public final class SiriusEventFileLogDestination: SiriusEventLogDestination, @unchecked Sendable {

    // MARK: - Static Instance Tracking

    private static let instancesLock = NSLock()
    nonisolated(unsafe) private static var instances = NSHashTable<SiriusEventFileLogDestination>.weakObjects()

    /// Flushes all active event file log destinations immediately.
    /// Call from application termination handlers to prevent log loss.
    public static func flushAll() {
        instancesLock.lock()
        let allInstances = instances.allObjects
        instancesLock.unlock()

        for instance in allInstances {
            instance.flush()
        }
    }

    private static func register(_ instance: SiriusEventFileLogDestination) {
        instancesLock.lock()
        instances.add(instance)
        instancesLock.unlock()
    }

    // MARK: - Rotation

    public struct RotationPolicy: Sendable {
        public let maxFileSize: UInt64
        public let maxFileCount: Int

        public init(maxFileSize: UInt64, maxFileCount: Int) {
            self.maxFileSize = maxFileSize
            self.maxFileCount = max(maxFileCount, 1)
        }
    }

    // MARK: - Properties

    private let fileURL: URL
    private let rotationPolicy: RotationPolicy?
    private let queue: DispatchQueue
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64

    private let bufferCapacity: Int
    private var buffer: Data
    private var flushTimer: DispatchSourceTimer?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Init

    public init(
        fileURL: URL,
        bufferCapacity: Int = 65_536,
        flushInterval: TimeInterval = 1.0
    ) {
        self.fileURL = fileURL
        self.rotationPolicy = nil
        self.queue = DispatchQueue(label: "so.libsirius.SiriusKit.event-logger.file.\(fileURL.lastPathComponent)")
        self.currentFileSize = 0
        self.fileHandle = nil
        self.bufferCapacity = bufferCapacity
        self.buffer = Data(capacity: bufferCapacity)
        openOrCreateFile()
        startFlushTimer(interval: flushInterval)
        Self.register(self)
    }

    public init(
        fileURL: URL,
        rotationPolicy: RotationPolicy,
        bufferCapacity: Int = 65_536,
        flushInterval: TimeInterval = 1.0
    ) {
        self.fileURL = fileURL
        self.rotationPolicy = rotationPolicy
        self.queue = DispatchQueue(label: "so.libsirius.SiriusKit.event-logger.file.\(fileURL.lastPathComponent)")
        self.currentFileSize = 0
        self.fileHandle = nil
        self.bufferCapacity = bufferCapacity
        self.buffer = Data(capacity: bufferCapacity)
        openOrCreateFile()
        startFlushTimer(interval: flushInterval)
        Self.register(self)
    }

    deinit {
        flushTimer?.cancel()
        if !buffer.isEmpty {
            fileHandle?.write(buffer)
        }
        fileHandle?.closeFile()
    }

    // MARK: - SiriusEventLogDestination

    public func write(message: String) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)\n"

        guard let data = formatted.data(using: .utf8) else { return }

        queue.sync {
            buffer.append(data)
            if buffer.count >= bufferCapacity {
                _flushBuffer()
            }
        }
    }

    // MARK: - Flush

    public func flush() {
        queue.sync {
            _flushBuffer()
        }
    }

    /// Must be called on `queue`.
    private func _flushBuffer() {
        guard !buffer.isEmpty else { return }

        if let policy = rotationPolicy, currentFileSize + UInt64(buffer.count) > policy.maxFileSize {
            rotateFiles()
        }

        fileHandle?.write(buffer)
        currentFileSize += UInt64(buffer.count)
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Timer

    private func startFlushTimer(interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?._flushBuffer()
        }
        timer.resume()
        flushTimer = timer
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

        let oldestURL = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: maxIndex)
        try? FileManager.default.removeItem(at: oldestURL)

        for i in stride(from: maxIndex - 1, through: 1, by: -1) {
            let src = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: i)
            let dst = rotatedFileURL(directory: directory, baseName: baseName, ext: ext, index: i + 1)
            try? FileManager.default.moveItem(at: src, to: dst)
        }

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
