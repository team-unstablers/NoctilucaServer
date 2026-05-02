//
//  FileTransferCoordinator.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//

import Foundation

import Cocoa

import SiriusKit

/// 수신 측에서 파일 다운로드를 조율하는 클래스.
/// macOS에서는 placeholder 파일 + NSFilePresenter를 통해
/// pasteboard에서 해당 URL을 읽으려 할 때 원격에서 파일을 다운로드한다.
final class FileTransferCoordinator: NSObject, Sendable {
    private let logger = NoctilucaLogger(category: "FileTransferCoordinator")

    /// 파일 다운로드를 수행할 채널 (weak)
    nonisolated(unsafe) private weak var clipboardChannel: ClipboardChannel?

    /// delegate 콜백용 작업 큐
    let operationQueue: OperationQueue

    init(clipboardChannel: ClipboardChannel?) {
        self.clipboardChannel = clipboardChannel
        self.operationQueue = OperationQueue()
        self.operationQueue.name = "FileTransferCoordinator"
        self.operationQueue.qualityOfService = .userInitiated
        super.init()
    }

    // MARK: - PendingFileTransfer 생성

    /// 메타데이터로부터 PendingFileTransfer를 생성한다.
    /// 디렉토리인 경우 서버에 listing을 요청하여 재귀적으로 하위 항목을 미리 생성한다.
    func preparePendingTransfer(for metadata: FileTransferMetadata) async throws -> PendingFileTransfer {
        let root = PendingFileTransfer(coordinator: self, metadata: metadata)
        if metadata.isDirectory {
            try await populateChildren(of: root, metadata: metadata)
        }
        return root
    }

    private func populateChildren(of parent: PendingFileTransfer, metadata: FileTransferMetadata) async throws {
        let listing = try await requestDirectoryListing(metadata: metadata)

        for entry in listing {
            guard entry.hasSafeName else {
                logger.warning("Rejected directory entry with unsafe name: \(entry.name)")
                continue
            }

            let childMetadata = FileTransferMetadata(
                name: entry.name,
                path: metadata.path + "/" + entry.name,
                size: entry.size,
                contentType: entry.contentType
            )

            let child = PendingFileTransfer(
                coordinator: self,
                metadata: childMetadata,
                parentURL: parent.presentedItemURL!
            )
            parent.addChild(child)

            if entry.isDirectory {
                try await populateChildren(of: child, metadata: childMetadata)
            }
        }
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

            // 전송 중 감지된 size overflow / EOF mismatch가 있으면 결과 파일을 폐기한다.
            if let transferError = channel.transferError {
                logger.error("Transfer failed, discarding temp file: \(transferError)")
                try? fm.removeItem(at: tempURL)
                throw transferError
            }

            let attr = try FileManager.default.attributesOfItem(atPath: tempURL.path())

            if let size = attr[.size] as? UInt64,
               size != metadata.size {
                logger.error("file size mismatch: expected \(metadata.size) but got \(size)")
            }

            // destination 부모 디렉토리 확보 후 이동
            let parentDir = destinationURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
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
            guard entry.hasSafeName else {
                logger.warning("Rejected directory entry with unsafe name: \(entry.name)")
                continue
            }

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

        if let transferError = channel.transferError {
            logger.error("Directory listing transfer failed: \(transferError)")
            throw transferError
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
///
/// 디렉토리의 경우 `FileTransferCoordinator.preparePendingTransfer(for:)`를 통해
/// 재귀적으로 하위 항목의 PendingFileTransfer를 미리 생성한다.
class PendingFileTransfer: NSObject, NSFilePresenter, @unchecked Sendable { // TODO: Sendable 준수
    private let logger = NoctilucaLogger(category: "PendingFileTransfer")

    /// 다운로드 완료 후 파일을 유지하는 시간 (초)
    private static let retentionInterval: TimeInterval = 60

    var presentedItemURL: URL?
    var presentedItemOperationQueue: OperationQueue

    let coordinator: FileTransferCoordinator
    let metadata: FileTransferMetadata

    /// 디렉토리인 경우 하위 항목의 PendingFileTransfer들
    private(set) var children: [PendingFileTransfer] = []

    /// 최상위(root) 항목인지 여부. root만 컨테이너 디렉토리를 삭제한다.
    private let isRoot: Bool

    /// 진행 중이거나 완료된 다운로드 Task.
    /// 여러 reader가 동시에 접근해도 같은 Task를 await한다.
    private var downloadTask: Task<Void, Error>?

    /// cleanup 예약 Task
    private var cleanupTask: Task<Void, Never>?

    /// 최상위 항목용 init. `{tmpDir}/{UUID}/{name}` 경로를 생성한다.
    init(coordinator: FileTransferCoordinator, metadata: FileTransferMetadata) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(metadata.name)

        self.coordinator = coordinator
        self.metadata = metadata
        self.presentedItemURL = tempURL
        self.presentedItemOperationQueue = coordinator.operationQueue
        self.isRoot = true

        super.init()

        createPlaceholder(at: tempURL)

        if !metadata.isDirectory {
            NSFileCoordinator.addFilePresenter(self)
        }
    }

    /// 하위 항목용 init. 부모 디렉토리 아래에 생성된다.
    init(coordinator: FileTransferCoordinator, metadata: FileTransferMetadata, parentURL: URL) {
        let tempURL = parentURL.appendingPathComponent(metadata.name)

        self.coordinator = coordinator
        self.metadata = metadata
        self.presentedItemURL = tempURL
        self.presentedItemOperationQueue = coordinator.operationQueue
        self.isRoot = false

        super.init()

        createPlaceholder(at: tempURL)

        if !metadata.isDirectory {
            NSFileCoordinator.addFilePresenter(self)
        }
    }

    private func createPlaceholder(at url: URL) {
        let fm = FileManager.default

        // 보안: metadata.name이 경로 분리자/`..` 등을 포함하면 placeholder 생성을 거부한다.
        // `appendingPathComponent`는 `..`를 리터럴로 포함시키므로 이를 막지 않으면
        // url이 UUID 컨테이너/부모 디렉토리를 벗어날 수 있다.
        guard metadata.name.isSafePathComponent else {
            logger.error("Refused to create placeholder for unsafe metadata.name: \(self.metadata.name)")
            return
        }

        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if metadata.isDirectory {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            fm.createFile(atPath: url.path, contents: nil)
            // sparse file: 디스크 블록을 할당하지 않고 파일 크기만 설정
            if metadata.size > 0 {
                let fd = open(url.path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
                if fd >= 0 {
                    ftruncate(fd, off_t(metadata.size))
                    close(fd)
                }
            }
        }
    }

    deinit {
        downloadTask?.cancel()
        cleanupTask?.cancel()
        if !metadata.isDirectory, let url = presentedItemURL, FileManager.default.fileExists(atPath: url.path) {
            NSFileCoordinator.removeFilePresenter(self)
        }
        if isRoot {
            removeFiles()
        }
    }

    /// NSFileCoordinator 등록을 해제하고 즉시 정리한다.
    func invalidate() {
        downloadTask?.cancel()
        cleanupTask?.cancel()

        for child in children {
            child.invalidate()
        }
        children.removeAll()

        if !metadata.isDirectory, let url = presentedItemURL, FileManager.default.fileExists(atPath: url.path) {
            NSFileCoordinator.removeFilePresenter(self)
        }
        if isRoot {
            removeFiles()
        }
    }

    private func removeFiles() {
        guard let url = presentedItemURL else { return }
        // root의 UUID 컨테이너 디렉토리째로 삭제
        let containerURL = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: containerURL)
    }

    /// 하위 PendingFileTransfer를 추가한다.
    func addChild(_ child: PendingFileTransfer) {
        children.append(child)
    }

    /// 다운로드를 시작하거나, 이미 진행 중인 다운로드를 반환한다.
    private func ensureDownload() -> Task<Void, Error> {
        if let existing = downloadTask {
            return existing
        }

        let task = Task { [weak self] in
            guard let self, let url = self.presentedItemURL else {
                throw FileTransferError.sessionUnavailable
            }

            try await self.coordinator.downloadFile(metadata: self.metadata, to: url)
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

    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        guard !metadata.isDirectory else {
            reader(nil)
            return
        }

        let task = ensureDownload()

        Task {
            do {
                try await task.value
            } catch {
                self.logger.error("File download failed: \(self.metadata.name), error: \(error)")
            }

            reader { [weak self] in
                self?.scheduleCleanup()
            }
        }
    }
}
