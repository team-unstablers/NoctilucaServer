//
//  FileTransferCoordinator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/24/26.
//

import Foundation

#if os(macOS)
import Cocoa
#elseif os(iOS)
import UIKit
#endif

import SiriusKitClient
import UniformTypeIdentifiers

/// 수신 측에서 파일 다운로드를 조율하는 클래스.
/// macOS에서는 NSFilePromiseProviderDelegate를 구현하여
/// pasteboard의 file promise가 이행될 때 원격에서 파일을 다운로드한다.
/// iOS에서는 NSItemProvider를 생성하여 파일 다운로드를 지원한다.
class FileTransferCoordinator: NSObject {
    private let logger = NoctilucaLogger(category: "FileTransferCoordinator")

    /// 파일 다운로드를 수행할 채널 (weak)
    private weak var clipboardChannel: ClipboardChannel?

    /// delegate 콜백용 작업 큐
    let operationQueue: OperationQueue

    init(clipboardChannel: ClipboardChannel?) {
        self.clipboardChannel = clipboardChannel
        self.operationQueue = OperationQueue()
        self.operationQueue.name = "FileTransferCoordinator"
        self.operationQueue.qualityOfService = .userInitiated
        super.init()
    }

    // MARK: - Download

    /// 단일 파일을 다운로드하여 destinationURL에 저장합니다.
    func downloadFile(metadata: FileTransferMetadata, to destinationURL: URL, progress: Progress? = nil) async throws {
        guard let session = clipboardChannel?.clientSession else {
            throw FileTransferError.sessionUnavailable
        }

        let argsSet = TransferChannelArgumentsSet(
            purpose: .fileTransfer,
            direction: .download,
            args: [metadata.name, metadata.path, "0", String(metadata.size)]
        )

        guard let channel = try await session.channelManager.openChannel(
            for: .transfer,
            identifier: ChannelIdentifier(),
            args: argsSet.serialize()
        ) as? TransferChannel else {
            throw FileTransferError.channelOpenFailed
        }

        guard let dataStream = channel.dataStream else {
            throw FileTransferError.noDataStream
        }

        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fm.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        do {
            for await chunk in dataStream {
                fileHandle.write(chunk)
                progress?.completedUnitCount += Int64(chunk.count)
            }
            try fileHandle.close()

            // destination으로 이동
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: tempURL, to: destinationURL)
        } catch {
            try? fileHandle.close()
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }

    /// 디렉토리를 재귀적으로 다운로드합니다.
    func downloadDirectory(metadata: FileTransferMetadata, to destinationURL: URL) async throws {
        // 1. 디렉토리 리스팅 요청
        let listing = try await requestDirectoryListing(metadata: metadata)

        // 2. 로컬에 디렉토리 생성
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // 3. 각 항목 다운로드
        for entry in listing {
            let childURL = destinationURL.appendingPathComponent(entry.name)
            let childMetadata = FileTransferMetadata(
                name: entry.name,
                path: metadata.path + "/" + entry.name,
                size: entry.size,
                contentType: entry.contentType
            )

            if entry.isDirectory {
                try await downloadDirectory(metadata: childMetadata, to: childURL)
            } else {
                try await downloadFile(metadata: childMetadata, to: childURL)
            }
        }
    }

    private func requestDirectoryListing(metadata: FileTransferMetadata) async throws -> [DirectoryEntry] {
        guard let session = clipboardChannel?.clientSession else {
            throw FileTransferError.sessionUnavailable
        }

        let argsSet = TransferChannelArgumentsSet(
            purpose: .fileTransfer,
            direction: .download,
            args: [metadata.name, metadata.path, "0", "0"]
        )

        guard let channel = try await session.channelManager.openChannel(
            for: .transfer,
            identifier: ChannelIdentifier(),
            args: argsSet.serialize()
        ) as? TransferChannel else {
            throw FileTransferError.channelOpenFailed
        }

        guard let dataStream = channel.dataStream else {
            throw FileTransferError.noDataStream
        }

        var data = Data()
        for await chunk in dataStream {
            data += chunk
        }

        return try JSONDecoder().decode([DirectoryEntry].self, from: data)
    }
}

// MARK: - PendingFileTransfer

/// NSFilePresenter를 구현하여 placeholder 파일에 대한 읽기 요청 시
/// 원격에서 파일을 다운로드하는 클래스.
/// NSFileCoordinator에 등록하면, 다른 프로세스가 해당 파일을 읽으려 할 때
/// relinquishPresentedItem(toReader:)가 호출되어 실제 다운로드가 수행된다.
///
/// 같은 파일을 여러 곳에 붙여넣기하는 경우를 지원하기 위해,
/// 다운로드 Task를 캐싱하고 다운로드 완료 후에도 파일을 일정 시간 유지한다.
class PendingFileTransfer: NSObject, NSFilePresenter {
    private let logger = NoctilucaLogger(category: "PendingFileTransfer")

    /// 다운로드 완료 후 파일을 유지하는 시간 (초)
    private static let retentionInterval: TimeInterval = 60

    var presentedItemURL: URL?
    var presentedItemOperationQueue: OperationQueue

    let coordinator: FileTransferCoordinator
    let metadata: FileTransferMetadata

    /// 진행 중이거나 완료된 다운로드 Task.
    /// 여러 reader가 동시에 접근해도 같은 Task를 await한다.
    private var downloadTask: Task<Void, Error>?

    /// cleanup 예약 Task
    private var cleanupTask: Task<Void, Never>?

    init(coordinator: FileTransferCoordinator, metadata: FileTransferMetadata) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(metadata.name)

        let fm = FileManager.default
        try? fm.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if metadata.isDirectory {
            try? fm.createDirectory(at: tempURL, withIntermediateDirectories: true)
        } else {
            fm.createFile(atPath: tempURL.path, contents: nil)
            // sparse file: 디스크 블록을 할당하지 않고 파일 크기만 설정
            if metadata.size > 0 {
                let fd = open(tempURL.path, O_WRONLY)
                if fd >= 0 {
                    ftruncate(fd, off_t(metadata.size))
                    close(fd)
                }
            }
        }

        self.coordinator = coordinator
        self.metadata = metadata
        self.presentedItemURL = tempURL
        self.presentedItemOperationQueue = coordinator.operationQueue

        super.init()

        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        downloadTask?.cancel()
        cleanupTask?.cancel()
        NSFileCoordinator.removeFilePresenter(self)
        removeFiles()
    }

    /// NSFileCoordinator 등록을 해제하고 즉시 정리한다.
    func invalidate() {
        downloadTask?.cancel()
        cleanupTask?.cancel()
        NSFileCoordinator.removeFilePresenter(self)
        removeFiles()
    }

    private func removeFiles() {
        let containerURL = presentedItemURL!.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: containerURL)
    }

    /// 다운로드를 시작하거나, 이미 진행 중인 다운로드를 반환한다.
    private func ensureDownload() -> Task<Void, Error> {
        if let existing = downloadTask {
            return existing
        }

        let task = Task { [weak self] in
            guard let self else { throw FileTransferError.sessionUnavailable }

            if self.metadata.isDirectory {
                try await self.coordinator.downloadDirectory(metadata: self.metadata, to: self.presentedItemURL!)
            } else {
                try await self.coordinator.downloadFile(metadata: self.metadata, to: self.presentedItemURL!)
            }

            self.logger.info("File downloaded: \(self.metadata.name)")
        }

        downloadTask = task
        return task
    }

    /// 다운로드 완료 후 일정 시간 뒤에 파일을 정리하도록 예약한다.
    private func scheduleCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PendingFileTransfer.retentionInterval))

            guard !Task.isCancelled, let self else { return }
            self.logger.info("Retention expired, cleaning up: \(self.metadata.name)")
            self.invalidate()
        }
    }

    // MARK: - NSFilePresenter

    func relinquishPresentedItem(toReader reader: @escaping ((() -> Void)?) -> Void) {
        let task = ensureDownload()
        
        print("reqlinquishPresentedItem")

        Task {
            do {
                try await task.value
            } catch {
                self.logger.error("File download failed: \(self.metadata.name), error: \(error)")
            }

            reader { [weak self] in
                // reader 완료 시 cleanup 타이머를 (재)시작
                self?.scheduleCleanup()
            }
        }
    }
}

// MARK: - macOS: NSFilePromiseProviderDelegate

#if os(macOS)
extension FileTransferCoordinator: NSFilePromiseProviderDelegate {
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        guard let metadata = filePromiseProvider.userInfo as? FileTransferMetadata else {
            return "unknown"
        }
        return metadata.name
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let metadata = filePromiseProvider.userInfo as? FileTransferMetadata else {
            completionHandler(FileTransferError.fileNotFound(path: "unknown"))
            return
        }

        Task {
            do {
                if metadata.isDirectory {
                    try await self.downloadDirectory(metadata: metadata, to: url)
                } else {
                    try await self.downloadFile(metadata: metadata, to: url)
                }
                completionHandler(nil)
            } catch {
                self.logger.error("File promise fulfillment failed: \(error)")
                completionHandler(error)
            }
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        return self.operationQueue
    }
}
#endif

// MARK: - iOS: NSItemProvider 생성

#if os(iOS)
extension FileTransferCoordinator {
    /// PendingFileTransfer를 생성하고 그 placeholder URL을 제공하는 NSItemProvider를 반환한다.
    /// 실제 다운로드는 수신 앱이 NSFileCoordinator를 통해 파일에 접근할 때 수행된다.
    func createItemProvider(for metadata: FileTransferMetadata) -> (NSItemProvider, PendingFileTransfer) {
        let pending = PendingFileTransfer(coordinator: self, metadata: metadata)

        let itemProvider = NSItemProvider()
        itemProvider.suggestedName = metadata.name

        let utType: UTType
        if metadata.isDirectory {
            utType = .folder
        } else {
            utType = UTType(mimeType: metadata.contentType) ?? .data
        }

        let pendingURL = pending.presentedItemURL
        itemProvider.registerFileRepresentation(
            for: utType,
            visibility: .all,
            openInPlace: false
        ) { completion in
            completion(pendingURL, false, nil)
            return Progress()
        }

        return (itemProvider, pending)
    }
}
#endif
