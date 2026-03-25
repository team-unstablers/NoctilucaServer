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
    func createItemProvider(for metadata: FileTransferMetadata) -> NSItemProvider {
        let itemProvider = NSItemProvider()
        itemProvider.suggestedName = metadata.name

        let utType: UTType
        if metadata.isDirectory {
            utType = .folder
        } else {
            utType = UTType(mimeType: metadata.contentType) ?? .data
        }

        itemProvider.registerFileRepresentation(
            for: utType,
            visibility: .all,
            openInPlace: false
        ) { [weak self] completion in
            guard let self = self else {
                completion(nil, false, FileTransferError.sessionUnavailable)
                return Progress()
            }

            let progress = Progress(totalUnitCount: max(Int64(metadata.size), 1))

            Task.detached { [weak self] in
                do {
                    guard let self else {
                        completion(nil, false, FileTransferError.sessionUnavailable)
                        return
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                    let tempURL = tempDir.appendingPathComponent(metadata.name)

                    if metadata.isDirectory {
                        try await self.downloadDirectory(metadata: metadata, to: tempURL)
                    } else {
                        try await self.downloadFile(metadata: metadata, to: tempURL, progress: progress)
                    }

                    progress.completedUnitCount = progress.totalUnitCount
                    completion(tempURL, false, nil)
                } catch {
                    self?.logger.error("iOS file transfer failed: \(error)")
                    completion(nil, false, error)
                }
            }

            return progress
        }

        return itemProvider
    }
}
#endif
