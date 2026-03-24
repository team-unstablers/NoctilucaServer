//
//  ClipboardChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation

import SiriusKitClient
import UniformTypeIdentifiers

class ClipboardChannel: Channel {
    let logger = NoctilucaLogger(category: "ClipboardChannel")

    private var remoteSubscription: ClipboardSubscription? = nil

    /// 마지막으로 보낸 ClipboardEvent의 omitted 데이터 스냅샷 (transfer 요청 응답용)
    private var lastSentSnapshot: ClipboardDataSnapshot? = nil

    /// 마지막으로 보낸 ClipboardEvent의 파일 전송 스냅샷 (file-transfer 요청 응답용)
    private var lastFileTransferSnapshot: FileTransferSnapshot? = nil

    /// 수신 측 FileTransferCoordinator (NSFilePromiseProvider delegate이므로 strong ref 필요)
    private(set) var fileTransferCoordinator: FileTransferCoordinator? = nil

    /// 현재 진행 중인 resolve 작업 (취소 가능)
    private var resolveTask: Task<Void, Never>? = nil

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .clipboardEvent:
            let event = try ClipboardEvent.fromProtobufBytes(frame.data)
            try await self.handleClipboardEvent(event)

        case .getClipboardRequest:
            let request = try GetClipboardRequest.fromProtobufBytes(frame.data)
            try await self.handleGetClipboardRequest(request)

        case .getClipboardResponse:
            let response = try GetClipboardResponse.fromProtobufBytes(frame.data)
            try await self.handleGetClipboardResponse(response)

        case .subscribeClipboardRequest:
            let request = try SubscribeClipboardRequest.fromProtobufBytes(frame.data)
            try await self.handleSubscribeClipboardRequest(request)
        case .subscribeClipboardResponse:
            let response = try SubscribeClipboardResponse.fromProtobufBytes(frame.data)
            try await self.handleSubscribeClipboardResponse(response)
        case .unsubscribeClipboardRequest:
            let request = try UnsubscribeClipboardRequest.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeClipboardRequest(request)
        case .unsubscribeClipboardResponse:
            let response = try UnsubscribeClipboardResponse.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeClipboardResponse(response)

        default:
            logger.warning("Received unknown opcode: \(frame.opcode)")
        }
    }

    // MARK: - Snapshot Management

    /// ClipboardSubscription에서 이벤트 발송 시 omitted 데이터 스냅샷을 저장합니다.
    func storeSnapshot(_ snapshot: ClipboardDataSnapshot) {
        self.lastSentSnapshot = snapshot
    }

    /// 파일 전송 스냅샷을 저장합니다.
    func storeFileTransferSnapshot(_ snapshot: FileTransferSnapshot) {
        self.lastFileTransferSnapshot = snapshot
    }

    // MARK: - Transfer Serving

    /// FeatureProvider로부터 호출됨: 상대방이 clipboard-data TransferChannel을 열었을 때
    func serveTransferData(_ transferChannel: TransferChannel, itemIndex: Int, representationIndex: Int) {
        Task {
            guard let data = lastSentSnapshot?.get(itemIndex: itemIndex, reprIndex: representationIndex) else {
                logger.warning("No snapshot data for item=\(itemIndex), repr=\(representationIndex)")
                try? await transferChannel.close()
                return
            }

            do {
                try await transferChannel.sendStartNotification(TransferStartNotification(
                    name: "clipboard-data",
                    totalSize: UInt64(data.count),
                    contentType: "application/octet-stream",
                    description: "Omitted clipboard data (item=\(itemIndex), repr=\(representationIndex))",
                    sha256sum: Data()
                ))
                try await transferChannel.write(data)
            } catch {
                logger.error("Failed to serve clipboard transfer: \(error)")
            }
        }
    }

    /// FeatureProvider로부터 호출됨: 상대방이 file-transfer TransferChannel을 열었을 때
    func serveFileTransferData(_ transferChannel: TransferChannel, name: String, path: URL, offset: Int64, length: Int64) {
        Task {
            // 보안 검증: 요청된 경로가 마지막 clipboard copy의 파일인지 확인
            guard let snapshot = lastFileTransferSnapshot,
                  snapshot.validatePath(path.path) else {
                logger.warning("File transfer path validation failed: \(path.path)")
                try? await transferChannel.close()
                return
            }

            let fm = FileManager.default
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
                logger.warning("File not found for transfer: \(path.path)")
                try? await transferChannel.close()
                return
            }

            do {
                if isDirectory.boolValue {
                    let contents = try fm.contentsOfDirectory(
                        at: path,
                        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
                    )

                    let entries: [DirectoryEntry] = contents.compactMap { url in
                        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                        let isDir = resourceValues?.isDirectory ?? false
                        let size = UInt64(resourceValues?.fileSize ?? 0)
                        let contentType = isDir
                            ? FileTransferContentType.directory
                            : (UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream")

                        return DirectoryEntry(name: url.lastPathComponent, contentType: contentType, size: size)
                    }

                    let jsonData = try JSONEncoder().encode(entries)

                    try await transferChannel.sendStartNotification(TransferStartNotification(
                        name: name,
                        totalSize: UInt64(jsonData.count),
                        contentType: "application/json",
                        description: "Directory listing for \(name)",
                        sha256sum: Data()
                    ))
                    try await transferChannel.write(jsonData)

                } else {
                    let attrs = try fm.attributesOfItem(atPath: path.path)
                    let fileSize = (attrs[.size] as? UInt64) ?? 0
                    let actualLength = length > 0 ? length : Int64(fileSize) - offset
                    let mimeType = UTType(filenameExtension: path.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

                    try await transferChannel.sendStartNotification(TransferStartNotification(
                        name: name,
                        totalSize: UInt64(actualLength),
                        contentType: mimeType,
                        description: "File transfer: \(name)",
                        sha256sum: Data()
                    ))
                    try await transferChannel.writeFromFile(at: path, offset: offset, length: actualLength)
                }
            } catch {
                logger.error("Failed to serve file transfer: \(error)")
                try? await transferChannel.close()
            }
        }
    }

    // MARK: - Request Handlers (서버 → 클라이언트)

    private func handleSubscribeClipboardRequest(_ request: SubscribeClipboardRequest) async throws {
        /*
        let settings = SettingsStore.shared.settings.clipboard

        guard settings.enabled else {
            logger.info("Clipboard disabled, rejecting subscribe request (requestId=\(request.requestId))")
            try await send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
                requestId: request.requestId,
                subscriptionId: nil
            ))
            return
        }
         */

        // 기존 구독이 있으면 제거
        if let existing = remoteSubscription {
            await existing.destroy()
            remoteSubscription = nil
        }

        let subscription = ClipboardSubscription()
        subscription.channel = self
        await subscription.setup()

        remoteSubscription = subscription

        logger.info("Clipboard subscription created (id=\(subscription.id), requestId=\(request.requestId))")

        try await send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
            requestId: request.requestId,
            subscriptionId: subscription.id
        ))
    }

    private func handleUnsubscribeClipboardRequest(_ request: UnsubscribeClipboardRequest) async throws {
        guard let subscription = remoteSubscription else {
            logger.warning("No active subscription to unsubscribe (requestId=\(request.requestId))")
            try await send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
                requestId: request.requestId,
                subscriptionId: request.subscriptionId,
                isSuccess: false
            ))
            return
        }

        let subscriptionId = subscription.id
        await subscription.destroy()
        remoteSubscription = nil

        logger.info("Clipboard subscription removed (id=\(subscriptionId), requestId=\(request.requestId))")

        try await send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId,
            isSuccess: true
        ))
    }

    private func handleGetClipboardRequest(_ request: GetClipboardRequest) async throws {
        /*
        let settings = SettingsStore.shared.settings.clipboard

        guard settings.enabled else {
            logger.info("Clipboard disabled, rejecting get request (requestId=\(request.requestId))")
            try await send(opcode: .getClipboardResponse, message: GetClipboardResponse(
                requestId: request.requestId,
                success: false,
                items: []
            ))
            return
        }
         */

        let items = await ClipboardManager.shared.current()

        try await send(opcode: .getClipboardResponse, message: GetClipboardResponse(
            requestId: request.requestId,
            success: true,
            items: items
        ))
    }

    private func handleClipboardEvent(_ event: ClipboardEvent) async throws {
        /*
        let settings = SettingsStore.shared.settings.clipboard

        guard settings.enabled else { return }

        // syncDirection 체크: remoteToLocal 또는 bidirectional일 때만 적용
        guard settings.syncDirection == .remoteToLocal ||
              settings.syncDirection == .bidirectional else {
            return
        }
         */

        // 진행 중인 resolve 취소
        resolveTask?.cancel()

        resolveTask = Task { [weak self] in
            guard let self = self else { return }

            var resolvedItems: [ClipboardItem] = []
            var fileTransferItems: [(Int, FileTransferMetadata)] = []

            for (itemIndex, item) in event.items.enumerated() {
                // 파일 전송 아이템인지 체크
                if let fileRepr = item.representations.first(where: {
                    $0.contentType == FileTransferContentType.fileTransfer
                }),
                   let data = fileRepr.data,
                   let metadata = try? JSONDecoder().decode(FileTransferMetadata.self, from: data) {
                    fileTransferItems.append((itemIndex, metadata))
                    continue
                }

                // 일반 아이템: 기존 omitted resolve 로직
                var resolvedRepresentations: [ClipboardData] = []

                for (reprIndex, representation) in item.representations.enumerated() {
                    guard !Task.isCancelled else { return }

                    if representation.flags.contains(.omitted) {
                        if let data = try? await self.resolveOmittedData(
                            itemIndex: itemIndex, reprIndex: reprIndex
                        ) {
                            resolvedRepresentations.append(ClipboardData(
                                contentType: representation.contentType,
                                size: UInt64(data.count),
                                data: data,
                                flags: []
                            ))
                        } else {
                            self.logger.warning("Failed to resolve omitted data (item=\(itemIndex), repr=\(reprIndex))")
                        }
                    } else if representation.data != nil {
                        resolvedRepresentations.append(representation)
                    }
                }

                if !resolvedRepresentations.isEmpty {
                    resolvedItems.append(ClipboardItem(representations: resolvedRepresentations))
                }
            }

            guard !Task.isCancelled else { return }

            if !fileTransferItems.isEmpty {
                let coordinator = FileTransferCoordinator(clipboardChannel: self)
                self.fileTransferCoordinator = coordinator
                self.logger.info("Applying remote clipboard event with file transfers (\(fileTransferItems.count) files, \(resolvedItems.count) items)")
                await ClipboardManager.shared.setWithFileTransfer(
                    items: resolvedItems,
                    fileTransferItems: fileTransferItems,
                    coordinator: coordinator
                )
            } else if !resolvedItems.isEmpty {
                self.logger.info("Applying remote clipboard event (\(resolvedItems.count) items)")
                await ClipboardManager.shared.set(items: resolvedItems)
            }
        }
    }

    // MARK: - Omitted Data Resolve

    private func resolveOmittedData(itemIndex: Int, reprIndex: Int) async throws -> Data? {
        guard let session = self.clientSession else { return nil }

        let argsSet = TransferChannelArgumentsSet(
            purpose: .clipboardData,
            direction: .download,
            args: [String(itemIndex), String(reprIndex)]
        )

        guard let channel = try await session.channelManager.openChannel(
            for: .transfer,
            identifier: ChannelIdentifier(),
            args: argsSet.serialize()
        ) as? TransferChannel else {
            return nil
        }

        guard let dataStream = channel.dataStream else { return nil }

        var data = Data()
        for await chunk in dataStream {
            data += chunk
        }

        return data.isEmpty ? nil : data
    }

    // MARK: - Response Handlers (클라이언트 → 서버 요청의 응답, 현재 미사용)

    private func handleGetClipboardResponse(_ response: GetClipboardResponse) async throws {
        logger.debug("Received GetClipboardResponse (requestId=\(response.requestId), success=\(response.success)) - not implemented")
    }

    private func handleSubscribeClipboardResponse(_ response: SubscribeClipboardResponse) async throws {
        logger.debug("Received SubscribeClipboardResponse (requestId=\(response.requestId)) - not implemented")
    }

    private func handleUnsubscribeClipboardResponse(_ response: UnsubscribeClipboardResponse) async throws {
        logger.debug("Received UnsubscribeClipboardResponse (requestId=\(response.requestId)) - not implemented")
    }

    // MARK: - Stream Lifecycle

    override func handleStreamClose() {
        resolveTask?.cancel()
        if let subscription = remoteSubscription {
            Task { @MainActor in
                subscription.destroy()
            }
            remoteSubscription = nil
        }
        lastSentSnapshot = nil
        lastFileTransferSnapshot = nil
        fileTransferCoordinator = nil
        super.handleStreamClose()
    }

    override func handleStreamError(error: any Error) {
        logger.error("ClipboardChannel stream error: \(error)")
        resolveTask?.cancel()
        if let subscription = remoteSubscription {
            Task { @MainActor in
                subscription.destroy()
            }
            remoteSubscription = nil
        }
        lastSentSnapshot = nil
        lastFileTransferSnapshot = nil
        fileTransferCoordinator = nil
        super.handleStreamError(error: error)
    }
}
