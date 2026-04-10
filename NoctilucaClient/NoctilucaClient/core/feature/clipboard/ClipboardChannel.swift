//
//  ClipboardChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation

import SiriusKitClient
import UniformTypeIdentifiers

// MARK: - ClipboardChannelState

actor ClipboardChannelState {
    var remoteSubscription: ClipboardSubscription? = nil

    /// 클라이언트가 서버에게 보낸 subscribe 요청으로 받은 subscriptionId
    var localSubscriptionId: UUID? = nil

    /// 마지막으로 보낸 ClipboardEvent의 omitted 데이터 스냅샷 (transfer 요청 응답용)
    var lastSentSnapshot: ClipboardDataSnapshot? = nil

    /// 마지막으로 보낸 ClipboardEvent의 파일 전송 스냅샷 (file-transfer 요청 응답용)
    var lastFileTransferSnapshot: FileTransferSnapshot? = nil

    /// 수신 측 FileTransferCoordinator (NSFilePromiseProvider delegate이므로 strong ref 필요)
    private(set) var fileTransferCoordinator: FileTransferCoordinator? = nil

    /// 현재 진행 중인 resolve 작업 (취소 가능)
    var resolveTask: Task<Void, Never>? = nil

    func storeSnapshot(_ snapshot: ClipboardDataSnapshot) {
        self.lastSentSnapshot = snapshot
    }

    func storeFileTransferSnapshot(_ snapshot: FileTransferSnapshot) {
        self.lastFileTransferSnapshot = snapshot
    }

    func setFileTransferCoordinator(_ coordinator: FileTransferCoordinator?) {
        self.fileTransferCoordinator = coordinator
    }

    func setRemoteSubscription(_ subscription: ClipboardSubscription?) {
        self.remoteSubscription = subscription
    }

    func getRemoteSubscription() -> ClipboardSubscription? {
        return remoteSubscription
    }

    func setLocalSubscriptionId(_ id: UUID?) {
        self.localSubscriptionId = id
    }

    func getLocalSubscriptionId() -> UUID? {
        return localSubscriptionId
    }

    func setResolveTask(_ task: Task<Void, Never>?) {
        self.resolveTask = task
    }
}

// MARK: - ClipboardChannel

final class ClipboardChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    private static let defaultServiceClass: ServiceClass = .background

    let logger = NoctilucaLogger(category: "ClipboardChannel")

    /// 세션 설정에서 주입된 클립보드 설정. 초기화 시점이나 이후에 설정될 수 있으므로
    /// nonisolated(unsafe)로 두고 세션 생명주기 동안 변경되지 않음을 가정합니다.
    nonisolated(unsafe) var clipboardSettings: SessionSettings.Clipboard = .init()

    let state = ClipboardChannelState()

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

    // MARK: - Snapshot Management

    /// ClipboardSubscription에서 이벤트 발송 시 omitted 데이터 스냅샷을 저장합니다.
    func storeSnapshot(_ snapshot: ClipboardDataSnapshot) {
        Task {
            await state.storeSnapshot(snapshot)
        }
    }

    /// 파일 전송 스냅샷을 저장합니다.
    func storeFileTransferSnapshot(_ snapshot: FileTransferSnapshot) {
        Task {
            await state.storeFileTransferSnapshot(snapshot)
        }
    }

    // MARK: - Transfer Serving

    /// FeatureProvider로부터 호출됨: 상대방이 clipboard-data TransferChannel을 열었을 때
    func serveTransferData(_ transferChannel: TransferChannel, itemIndex: Int, representationIndex: Int) {
        Task {
            let lastSentSnapshot = await state.lastSentSnapshot
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
            } catch {
                logger.error("Failed to serve clipboard transfer: \(error)")
            }
        }
    }

    /// FeatureProvider로부터 호출됨: 상대방이 file-transfer TransferChannel을 열었을 때
    func serveFileTransferData(_ transferChannel: TransferChannel, name: String, path: URL, offset: Int64, length: Int64) {
        Task {
            let lastFileTransferSnapshot = await state.lastFileTransferSnapshot
            // 보안 검증: 요청된 경로가 마지막 clipboard copy의 파일인지 확인
            guard let snapshot = lastFileTransferSnapshot,
                  snapshot.validatePath(path.path) else {
                logger.warning("File transfer path validation failed: \(path.path)")
                try? await transferChannel.handle.close()
                return
            }

            let fm = FileManager.default
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
                logger.warning("File not found for transfer: \(path.path)")
                try? await transferChannel.handle.close()
                return
            }

            // 보안 검증: 심볼릭 링크 해석 후 특수 파일(디바이스, 소켓 등) 거부
            let resolvedPath = path.resolvingSymlinksInPath()
            if let fileType = (try? fm.attributesOfItem(atPath: resolvedPath.path))?[.type] as? FileAttributeType,
               fileType != .typeRegular && fileType != .typeDirectory {
                logger.warning("Rejected file transfer for special file: \(path.path) (resolved: \(resolvedPath.path), type: \(fileType))")
                try? await transferChannel.handle.close()
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
                        description: "Directory listing for \(name)"
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
                        description: "File transfer: \(name)"
                    ))
                    try await transferChannel.writeFromFile(at: path, offset: offset, length: actualLength)
                }
            } catch {
                logger.error("Failed to serve file transfer: \(error)")
                try? await transferChannel.handle.close()
            }
        }
    }

    // MARK: - Request Handlers (서버 → 클라이언트)

    private func handleSubscribeClipboardRequest(_ request: SubscribeClipboardRequest) async throws {
        guard clipboardSettings.enabled else {
            logger.info("Clipboard disabled, rejecting subscribe request (requestId=\(request.requestId))")
            try await handle.send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
                requestId: request.requestId,
                isSuccess: false,
                subscriptionId: nil
            ))
            return
        }

        // 기존 구독이 있으면 제거
        if let existing = await state.remoteSubscription {
            await existing.destroy()
            await state.setRemoteSubscription(nil)
        }

        let subscription = ClipboardSubscription()
        subscription.channel = self
        subscription.clipboardSettings = self.clipboardSettings
        await subscription.setup()

        await state.setRemoteSubscription(subscription)

        logger.info("Clipboard subscription created (id=\(subscription.id), requestId=\(request.requestId))")

        try await handle.send(opcode: .subscribeClipboardResponse, message: SubscribeClipboardResponse(
            requestId: request.requestId,
            isSuccess: true,
            subscriptionId: subscription.id
        ))
    }

    private func handleUnsubscribeClipboardRequest(_ request: UnsubscribeClipboardRequest) async throws {
        guard let subscription = await state.remoteSubscription else {
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
        await state.setRemoteSubscription(nil)

        logger.info("Clipboard subscription removed (id=\(subscriptionId), requestId=\(request.requestId))")

        try await handle.send(opcode: .unsubscribeClipboardResponse, message: UnsubscribeClipboardResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId,
            isSuccess: true
        ))
    }

    private func handleGetClipboardRequest(_ request: GetClipboardRequest) async throws {
        guard clipboardSettings.enabled else {
            logger.info("Clipboard disabled, rejecting get request (requestId=\(request.requestId))")
            try await handle.send(opcode: .getClipboardResponse, message: GetClipboardResponse(
                requestId: request.requestId,
                success: false,
                items: []
            ))
            return
        }

        let items = await ClipboardManager.shared.current(settings: clipboardSettings)

        try await handle.send(opcode: .getClipboardResponse, message: GetClipboardResponse(
            requestId: request.requestId,
            success: true,
            items: items
        ))
    }

    private func handleClipboardEvent(_ event: ClipboardEvent) async throws {
        guard clipboardSettings.enabled else { return }

        // subscriptionId 검증
        let localSubscriptionId = await state.localSubscriptionId
        guard let localSubId = localSubscriptionId, event.subscriptionId == localSubId else {
            logger.warning("Received ClipboardEvent with unknown subscriptionId=\(event.subscriptionId), expected=\(String(describing: localSubscriptionId))")
            return
        }

        resolveAndApplyRemoteItems(event.items, allowFile: clipboardSettings.allowFile)
    }

    // MARK: - Remote Items Resolve & Apply

    /// 원격에서 수신한 클립보드 아이템을 resolve(omitted data 다운로드)하고 로컬 클립보드에 적용합니다.
    private func resolveAndApplyRemoteItems(_ items: [ClipboardItem], allowFile: Bool) {
        Task {
            await state.resolveTask?.cancel()

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
                    await self.state.setFileTransferCoordinator(coordinator)
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
            
            await state.setResolveTask(task)
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

    // MARK: - Response Handlers (클라이언트가 서버에게 보낸 요청의 응답)

    private func handleGetClipboardResponse(_ response: GetClipboardResponse) async throws {
        guard clipboardSettings.enabled else { return }

        guard response.success else {
            logger.warning("GetClipboardResponse failed (requestId=\(response.requestId))")
            return
        }

        guard !response.items.isEmpty else {
            logger.debug("GetClipboardResponse has no items (requestId=\(response.requestId))")
            return
        }

        logger.info("Applying GetClipboardResponse (requestId=\(response.requestId), items=\(response.items.count))")
        resolveAndApplyRemoteItems(response.items, allowFile: clipboardSettings.allowFile)
    }

    private func handleSubscribeClipboardResponse(_ response: SubscribeClipboardResponse) async throws {
        if response.isSuccess, let subscriptionId = response.subscriptionId {
            await state.setLocalSubscriptionId(subscriptionId)
            logger.info("Subscribe to server clipboard succeeded (subscriptionId=\(subscriptionId), requestId=\(response.requestId))")
        } else {
            await state.setLocalSubscriptionId(nil)
            logger.warning("Subscribe to server clipboard rejected (requestId=\(response.requestId))")
        }
    }

    private func handleUnsubscribeClipboardResponse(_ response: UnsubscribeClipboardResponse) async throws {
        if response.isSuccess {
            logger.info("Unsubscribe from server clipboard succeeded (subscriptionId=\(String(describing: response.subscriptionId)), requestId=\(response.requestId))")
        } else {
            logger.warning("Unsubscribe from server clipboard failed (requestId=\(response.requestId))")
        }
        await state.setLocalSubscriptionId(nil)
    }

    // MARK: - Stream Lifecycle

    private func cleanupSubscriptions() async {
        await state.resolveTask?.cancel()

        // 로컬 구독 해제 (best-effort unsubscribe 전송)
        if let localSubId = await state.localSubscriptionId {
            try? await self.handle.send(opcode: .unsubscribeClipboardRequest, message: UnsubscribeClipboardRequest(
                requestId: 0,
                subscriptionId: localSubId
            ))
            await state.setLocalSubscriptionId(nil)
        }

        // 리모트 구독 해제
        if let subscription = await state.remoteSubscription {
            await subscription.destroy()
            await state.setRemoteSubscription(nil)
        }

        await state.storeSnapshot(ClipboardDataSnapshot(items: []))
        await state.storeFileTransferSnapshot(FileTransferSnapshot(items: []))
        await state.setFileTransferCoordinator(nil)
    }

    func handleStreamClose() async {
        await cleanupSubscriptions()
    }

    func handleError(error: any Error) async {
        logger.error("ClipboardChannel stream error: \(error)")
        await cleanupSubscriptions()
    }
}

extension ClipboardChannel: Channel.HasFeature {
    var feature: SiriusFeature {
        return .clipboard
    }
}
