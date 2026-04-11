//
//  ClipboardChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation

import SiriusKit
import UniformTypeIdentifiers

// MARK: - Transfer EventType

extension SiriusEventLogger.EventType {
    struct Transfer {
        static let fileTransferStarted    = SiriusEventLogger.EventType(rawValue: "FILE_TRANSFER_STARTED")
        static let fileTransferCompleted  = SiriusEventLogger.EventType(rawValue: "FILE_TRANSFER_COMPLETED")
        static let fileTransferFailed     = SiriusEventLogger.EventType(rawValue: "FILE_TRANSFER_FAILED")
        static let clipboardDataServed    = SiriusEventLogger.EventType(rawValue: "CLIPBOARD_DATA_SERVED")
    }
}

// MARK: - ClipboardChannel

actor ClipboardChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    private static let defaultServiceClass: ServiceClass = .background

    private let logger = NoctilucaLogger(category: "ClipboardChannel")
    private var _eventLogger: SiriusEventLogger?
    
    private var remoteSubscription: ClipboardSubscription? = nil

    /// 서버가 클라이언트에게 보낸 subscribe 요청으로 받은 subscriptionId (bidirectional 시)
    private var localSubscriptionId: UUID? = nil

    /// 마지막으로 보낸 ClipboardEvent의 omitted 데이터 스냅샷 (transfer 요청 응답용)
    private var lastSentSnapshot: ClipboardDataSnapshot? = nil

    /// 마지막으로 보낸 ClipboardEvent의 파일 전송 스냅샷 (file-transfer 요청 응답용)
    private var lastFileTransferSnapshot: FileTransferSnapshot? = nil

    /// 수신 측 FileTransferCoordinator (NSFilePromiseProvider delegate이므로 strong ref 필요)
    private(set) var fileTransferCoordinator: FileTransferCoordinator? = nil

    /// 현재 진행 중인 resolve 작업 (취소 가능)
    private var resolveTask: Task<Void, Never>? = nil


    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음.
    nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<ClipboardChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle

        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
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
    
    fileprivate func setFileTransferCoordinator(_ coordinator: FileTransferCoordinator? = nil) {
        self.fileTransferCoordinator = coordinator
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

    // MARK: - Event Logger

    private func ensureEventLogger() -> SiriusEventLogger? {
        if let logger = self._eventLogger {
            return logger
        }
        
        guard let context = self.clientSession?.eventLoggerContext else { return nil }
        let logger = SiriusEventLogger("NoctilucaServer::Transfer", context: context)
        self._eventLogger = logger
        return logger
    }

    // MARK: - Transfer Serving

    /// FeatureProvider로부터 호출됨: 상대방이 clipboard-data TransferChannel을 열었을 때
    func serveTransferData(_ transferChannel: TransferChannel, itemIndex: Int, representationIndex: Int) {
        Task {
            guard let data = lastSentSnapshot?.get(itemIndex: itemIndex, reprIndex: representationIndex) else {
                logger.warning("No snapshot data for item=\(itemIndex), repr=\(representationIndex)")
                try? await transferChannel.handle.close()
                return
            }

            do {
                try await transferChannel.sendStartNotification(TransferStartNotification(
                    name: "clipboard-data",
                    totalSize: UInt64(data.count),
                    contentType: "application/octet-stream",
                    description: "Omitted clipboard data (item=\(itemIndex), repr=\(representationIndex))"
                ))
                try await transferChannel.write(data)
                ensureEventLogger()?.log(.Transfer.clipboardDataServed, args: [
                    "item_index": String(itemIndex),
                    "repr_index": String(representationIndex),
                    "size": String(data.count),
                ])
            } catch {
                logger.error("Failed to serve clipboard transfer: \(error)")
            }
        }
    }

    /// FeatureProvider로부터 호출됨: 상대방이 file-transfer TransferChannel을 열었을 때
    func serveFileTransferData(_ transferChannel: TransferChannel, name: String, path: URL, offset: Int64, length: Int64) {
        Task {
            let evLogger = ensureEventLogger()

            // 보안 검증: 요청된 경로가 마지막 clipboard copy의 파일인지 확인
            guard let snapshot = lastFileTransferSnapshot,
                  snapshot.validatePath(path.path) else {
                logger.warning("File transfer path validation failed: \(path.path)")
                evLogger?.log(.Transfer.fileTransferFailed, args: [
                    "name": name,
                    "reason": "path_validation_failed",
                ])
                try? await transferChannel.handle.close()
                return
            }

            let fm = FileManager.default
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
                logger.warning("File not found for transfer: \(path.path)")
                evLogger?.log(.Transfer.fileTransferFailed, args: [
                    "name": name,
                    "reason": "file_not_found",
                ])
                try? await transferChannel.handle.close()
                return
            }

            // 보안 검증: 심볼릭 링크 해석 후 특수 파일(디바이스, 소켓 등) 거부
            let resolvedPath = path.resolvingSymlinksInPath()
            if let fileType = (try? fm.attributesOfItem(atPath: resolvedPath.path))?[.type] as? FileAttributeType,
               fileType != .typeRegular && fileType != .typeDirectory {
                logger.warning("Rejected file transfer for special file: \(path.path) (resolved: \(resolvedPath.path), type: \(fileType))")
                evLogger?.log(.Transfer.fileTransferFailed, args: [
                    "name": name,
                    "reason": "special_file_rejected",
                ])
                try? await transferChannel.handle.close()
                return
            }

            evLogger?.log(.Transfer.fileTransferStarted, args: [
                "name": name,
                "is_directory": isDirectory.boolValue.description,
            ])

            do {
                if isDirectory.boolValue {
                    // 디렉토리: JSON 리스팅 전송
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
                        description: "Directory listing for \(name)"
                    ))
                    try await transferChannel.write(jsonData)

                    evLogger?.log(.Transfer.fileTransferCompleted, args: [
                        "name": name,
                        "type": "directory_listing",
                        "size": String(jsonData.count),
                    ])

                } else {
                    // 파일: 디스크에서 스트리밍 전송
                    let attrs = try fm.attributesOfItem(atPath: path.path)
                    let fileSize = (attrs[.size] as? UInt64) ?? 0
                    let actualLength = length > 0 ? length : Int64(fileSize) - offset
                    let mimeType = UTType(filenameExtension: path.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

                    try await transferChannel.sendStartNotification(TransferStartNotification(
                        name: name,
                        totalSize: UInt64(actualLength),
                        contentType: mimeType,
                        description: "File transfer: \(name)"
                    ))
                    try await transferChannel.writeFromFile(at: path, offset: offset, length: actualLength)

                    evLogger?.log(.Transfer.fileTransferCompleted, args: [
                        "name": name,
                        "type": "file",
                        "size": String(actualLength),
                        "content_type": mimeType,
                    ])
                    await AppNotification.fileTransferSent(fileName: name).post()
                }
            } catch {
                logger.error("Failed to serve file transfer: \(error)")
                evLogger?.log(.Transfer.fileTransferFailed, args: [
                    "name": name,
                    "reason": "exception",
                    "error": String(describing: error),
                ])
                try? await transferChannel.handle.close()
            }
        }
    }

    // MARK: - Request Handlers (클라이언트 → 서버)

    private func handleSubscribeClipboardRequest(_ request: SubscribeClipboardRequest) async throws {
        let settings = await SettingsStore.shared.settings.clipboard

        guard settings.enabled else {
            logger.info("Clipboard disabled, rejecting subscribe request (requestId=\(request.requestId))")
            try await handle.send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
                requestId: request.requestId,
                isSuccess: false,
                subscriptionId: nil
            ))
            return
        }

        // 기존 구독이 있으면 제거
        if let existing = remoteSubscription {
            await existing.destroy()
            remoteSubscription = nil
        }

        let subscription = await ClipboardSubscription()
        
        await subscription.setChannel(self)
        await subscription.setup()

        remoteSubscription = subscription

        logger.info("Clipboard subscription created (id=\(subscription.id), requestId=\(request.requestId))")

        try await handle.send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
            requestId: request.requestId,
            isSuccess: true,
            subscriptionId: subscription.id
        ))

        if settings.syncDirection == .bidirectional || settings.syncDirection == .remoteToLocal {
            try? await self.handle.send(opcode: .subscribeClipboardRequest, message: SubscribeClipboardRequest(requestId: 1, flags: 0))
        }
    }

    private func handleUnsubscribeClipboardRequest(_ request: UnsubscribeClipboardRequest) async throws {
        guard let subscription = remoteSubscription else {
            logger.warning("No active subscription to unsubscribe (requestId=\(request.requestId))")
            try await handle.send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
                requestId: request.requestId,
                subscriptionId: request.subscriptionId,
                isSuccess: false
            ))
            return
        }

        let subscriptionId = subscription.id
        await subscription.destroy()
        
        self.remoteSubscription = nil

        logger.info("Clipboard subscription removed (id=\(subscriptionId), requestId=\(request.requestId))")

        try await handle.send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId,
            isSuccess: true
        ))
    }

    private func handleGetClipboardRequest(_ request: GetClipboardRequest) async throws {
        let settings = await SettingsStore.shared.settings.clipboard

        guard settings.enabled else {
            logger.info("Clipboard disabled, rejecting get request (requestId=\(request.requestId))")
            try await handle.send(opcode: .getClipboardResponse, message: GetClipboardResponse(
                requestId: request.requestId,
                success: false,
                items: []
            ))
            return
        }

        let items = await ClipboardManager.shared.current()

        try await handle.send(opcode: .getClipboardResponse, message: GetClipboardResponse(
            requestId: request.requestId,
            success: true,
            items: items
        ))
    }

    private func handleClipboardEvent(_ event: ClipboardEvent) async throws {
        let settings = await SettingsStore.shared.settings.clipboard

        guard settings.enabled else { return }

        // syncDirection 체크: remoteToLocal 또는 bidirectional일 때만 적용
        guard settings.syncDirection == .remoteToLocal ||
              settings.syncDirection == .bidirectional else {
            return
        }

        // subscriptionId 검증
        let localSubscriptionId = self.localSubscriptionId
        guard let localSubId = localSubscriptionId, event.subscriptionId == localSubId else {
            logger.warning("Received ClipboardEvent with unknown subscriptionId=\(event.subscriptionId), expected=\(String(describing: localSubscriptionId))")
            return
        }

        resolveAndApplyRemoteItems(event.items, allowFile: settings.allowFile)
    }

    // MARK: - Remote Items Resolve & Apply

    /// 원격에서 수신한 클립보드 아이템을 resolve(omitted data 다운로드)하고 로컬 클립보드에 적용합니다.
    private func resolveAndApplyRemoteItems(_ items: [ClipboardItem], allowFile: Bool) {
        Task {
            await resolveTask?.cancel()

            let task = Task { [weak self] in
                guard let self = self else { return }

                var resolvedItems: [ClipboardItem] = []
                var fileTransferItems: [(Int, FileTransferMetadata)] = []

                for (itemIndex, item) in items.enumerated() {
                    // 파일 전송 아이템인지 체크
                    if let fileRepr = item.representations.first(where: {
                        $0.contentType == FileTransferContentType.fileTransfer
                    }),
                       let data = fileRepr.data,
                       let metadata = try? JSONDecoder().decode(FileTransferMetadata.self, from: data) {
                        fileTransferItems.append((itemIndex, metadata))
                        continue
                    }

                    // 일반 아이템: omitted resolve 로직
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

                if !fileTransferItems.isEmpty, allowFile {
                    let coordinator = FileTransferCoordinator(clipboardChannel: self)
                    await self.setFileTransferCoordinator(coordinator)
                    self.logger.info("Applying remote clipboard with file transfers (\(fileTransferItems.count) files, \(resolvedItems.count) items)")
                    await ClipboardManager.shared.setWithFileTransfer(
                        items: resolvedItems,
                        fileTransferItems: fileTransferItems,
                        coordinator: coordinator
                    )
                } else if !resolvedItems.isEmpty {
                    self.logger.info("Applying remote clipboard (\(resolvedItems.count) items)")
                    await ClipboardManager.shared.set(items: resolvedItems)
                }
            }
            
            resolveTask = task
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

    // MARK: - Response Handlers (서버가 클라이언트에게 보낸 요청의 응답)

    private func handleGetClipboardResponse(_ response: GetClipboardResponse) async throws {
        let settings = await SettingsStore.shared.settings.clipboard

        guard settings.enabled else { return }
        guard settings.syncDirection == .remoteToLocal ||
              settings.syncDirection == .bidirectional else { return }

        guard response.success else {
            logger.warning("GetClipboardResponse failed (requestId=\(response.requestId))")
            return
        }

        guard !response.items.isEmpty else {
            logger.debug("GetClipboardResponse has no items (requestId=\(response.requestId))")
            return
        }

        logger.info("Applying GetClipboardResponse (requestId=\(response.requestId), items=\(response.items.count))")
        resolveAndApplyRemoteItems(response.items, allowFile: settings.allowFile)
    }

    private func handleSubscribeClipboardResponse(_ response: SubscribeClipboardResponse) async throws {
        if response.isSuccess, let subscriptionId = response.subscriptionId {
            self.localSubscriptionId = subscriptionId
            logger.info("Subscribe to client clipboard succeeded (subscriptionId=\(subscriptionId), requestId=\(response.requestId))")
        } else {
            self.localSubscriptionId = nil
            logger.warning("Subscribe to client clipboard rejected (requestId=\(response.requestId))")
        }
    }

    private func handleUnsubscribeClipboardResponse(_ response: UnsubscribeClipboardResponse) async throws {
        if response.isSuccess {
            logger.info("Unsubscribe from client clipboard succeeded (subscriptionId=\(String(describing: response.subscriptionId)), requestId=\(response.requestId))")
        } else {
            logger.warning("Unsubscribe from client clipboard failed (requestId=\(response.requestId))")
        }
        self.localSubscriptionId = nil
    }

    // MARK: - Stream Lifecycle

    private func cleanupSubscriptions() async {
        await resolveTask?.cancel()

        // 로컬 구독 해제 (best-effort unsubscribe 전송)
        if let localSubId = self.localSubscriptionId {
            try? await self.handle.send(opcode: .unsubscribeClipboardRequest, message: UnsubscribeClipboardRequest(
                requestId: 0,
                subscriptionId: localSubId
            ))
            self.localSubscriptionId = nil
        }

        // 리모트 구독 해제
        await self.remoteSubscription?.destroy()
        remoteSubscription = nil
        
        storeSnapshot(ClipboardDataSnapshot())
        storeFileTransferSnapshot(FileTransferSnapshot())
        fileTransferCoordinator = nil
    }

    func handleStreamClose() async {
        await cleanupSubscriptions()
    }

    func handleError(error: any Error) async {
        logger.error("ClipboardChannel stream error: \(error)")
        await cleanupSubscriptions()
    }
}
