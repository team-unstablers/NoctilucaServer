//
//  ClipboardChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/23/26.
//

import Foundation

import SiriusKitClient
import UniformTypeIdentifiers

// MARK: - ClipboardLimits

/// ClipboardEvent / ClipboardItem 수신 시 적용되는 개수 상한.
///
/// mdproto 명세 (`SiriusProtocol/v1/channels/clipboard.mdproto.md`):
/// - `ClipboardItem.representations` MUST NOT exceed 32
/// - `ClipboardEvent.items` MUST NOT exceed 1024
///
/// 단일 hard reject 대신 두 단계 임계값으로 graceful degradation을 적용합니다.
/// - `(spec, warn]`: send-side 버그 가능성. warn 로그 + spec 까지 truncate.
/// - `(warn, hard)`: 의심스럽지만 살릴 수 있는 범위. error 로그 + spec 까지 truncate.
/// - `[hard, ∞)`: 의도적 abuse 의심. error 로그 + 해당 단위 (item 또는 message) 전체 drop.
private enum ClipboardLimits {
    /// `ClipboardEvent.items` 명세 상한.
    static let maxItems = 1024
    /// `ClipboardItem.representations` 명세 상한.
    static let maxRepresentationsPerItem = 32

    /// `ClipboardData.data` 인라인 본문 명세 상한 (128 KiB).
    /// 이 크기를 초과하는 데이터는 송신측이 `omitted` 플래그를 세팅하고 TransferChannel 로 전달해야 합니다.
    static let maxInlineDataBytes = 128 * 1024

    /// items 1.5x — minor overflow tolerance.
    static let itemsWarnThreshold = (maxItems * 3) / 2
    /// representations 1.5x — minor overflow tolerance.
    static let representationsWarnThreshold = (maxRepresentationsPerItem * 3) / 2
    /// 인라인 본문 1.5x — minor overflow tolerance (sender 버그 가능 영역).
    static let inlineDataWarnThreshold = (maxInlineDataBytes * 3) / 2

    /// items 32x — hard fail threshold.
    static let itemsHardThreshold = maxItems * 32
    /// representations 32x — hard fail threshold.
    static let representationsHardThreshold = maxRepresentationsPerItem * 32
}

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
            // 보안 검증: 요청된 경로가 마지막 clipboard copy의 파일인지 확인.
            // 통과 시 정규화된 URL을 반환받아 이후 I/O에 그대로 사용한다 (TOCTOU 회피).
            guard let snapshot = lastFileTransferSnapshot,
                  let safePath = snapshot.validatePath(path.path) else {
                logger.warning("File transfer path validation failed: \(path.path)")
                try? await transferChannel.handle.close()
                return
            }

            let fm = FileManager.default
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: safePath.path, isDirectory: &isDirectory) else {
                logger.warning("File not found for transfer: \(safePath.path)")
                try? await transferChannel.handle.close()
                return
            }

            // 특수 파일(디바이스, 소켓 등) 거부
            if let fileType = (try? fm.attributesOfItem(atPath: safePath.path))?[.type] as? FileAttributeType,
               fileType != .typeRegular && fileType != .typeDirectory {
                logger.warning("Rejected file transfer for special file: \(safePath.path) (type: \(fileType))")
                try? await transferChannel.handle.close()
                return
            }

            do {
                if isDirectory.boolValue {
                    let contents = try fm.contentsOfDirectory(
                        at: safePath,
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
                    // 파일: 검증된 safePath 사용
                    let attrs = try fm.attributesOfItem(atPath: safePath.path)
                    let fileSize = (attrs[.size] as? UInt64) ?? 0
                    let actualLength = length > 0 ? length : Int64(fileSize) - offset
                    let mimeType = UTType(filenameExtension: safePath.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

                    try await transferChannel.sendStartNotification(TransferStartNotification(
                        name: name,
                        totalSize: UInt64(actualLength),
                        contentType: mimeType,
                        description: "File transfer: \(name)"
                    ))
                    try await transferChannel.writeFromFile(at: safePath, offset: offset, length: actualLength)
                }
            } catch {
                logger.error("Failed to serve file transfer: \(error)")
                try? await transferChannel.handle.close()
            }
        }
    }

    // MARK: - Request Handlers (서버 → 클라이언트)

    @MainActor
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

    // MARK: - Limit Enforcement

    /// items / representations 가 hard threshold 를 초과했는지 검사합니다.
    ///
    /// - Returns: 위반 사유 문자열. nil이면 hard violation 없음 (soft 영역 또는 정상).
    private func detectHardViolation(_ items: [ClipboardItem]) -> String? {
        let itemCount = items.count
        let itemsSpec = ClipboardLimits.maxItems
        let itemsHard = ClipboardLimits.itemsHardThreshold

        if itemCount >= itemsHard {
            return "ClipboardEvent.items count \(itemCount) exceeds hard threshold \(itemsHard) (\(itemCount / itemsSpec)x spec_limit \(itemsSpec)). Treated as protocol violation per spec violation handling policy."
        }

        let repsSpec = ClipboardLimits.maxRepresentationsPerItem
        let repsHard = ClipboardLimits.representationsHardThreshold
        for (index, item) in items.enumerated() {
            let count = item.representations.count
            if count >= repsHard {
                return "ClipboardItem[\(index)].representations count \(count) exceeds hard threshold \(repsHard) (\(count / repsSpec)x spec_limit \(repsSpec)). Treated as protocol violation per spec violation handling policy."
            }
        }

        return nil
    }

    /// `ClipboardEvent.items` 개수가 spec 과 hard 사이일 때 truncate 합니다.
    /// 호출 전에 `detectHardViolation` 으로 hard 위반은 걸러져 있어야 합니다.
    private func truncateItemsToSpec(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let count = items.count
        let spec = ClipboardLimits.maxItems

        if count <= spec { return items }

        let warn = ClipboardLimits.itemsWarnThreshold
        if count > warn {
            logger.error("ClipboardEvent has \(count) items, significantly exceeding spec limit \(spec) — truncating to \(spec)")
        } else {
            logger.warning("ClipboardEvent has \(count) items, exceeding spec limit \(spec) — truncating to \(spec) (likely sender bug)")
        }
        return Array(items.prefix(spec))
    }

    /// `ClipboardItem.representations` 개수가 spec 과 hard 사이일 때 truncate 합니다.
    /// 호출 전에 `detectHardViolation` 으로 hard 위반은 걸러져 있어야 합니다.
    private func truncateRepresentationsToSpec(_ representations: [ClipboardData], itemIndex: Int) -> [ClipboardData] {
        let count = representations.count
        let spec = ClipboardLimits.maxRepresentationsPerItem

        if count <= spec { return representations }

        let warn = ClipboardLimits.representationsWarnThreshold
        if count > warn {
            logger.error("Item \(itemIndex) has \(count) representations, significantly exceeding spec limit \(spec) — truncating to \(spec)")
        } else {
            logger.warning("Item \(itemIndex) has \(count) representations, exceeding spec limit \(spec) — truncating to \(spec) (likely sender bug)")
        }
        return Array(representations.prefix(spec))
    }

    /// 단일 `ClipboardData.data` 인라인 본문 크기를 검사하고 accept / drop 을 결정합니다.
    /// spec(128 KiB) 와 warn(1.5x) 사이는 sender 버그 forgiveness 로 accept 합니다.
    /// warn 초과 시에는 Pattern B 에 따라 해당 representation 만 drop 하고 나머지는 유지합니다.
    ///
    /// - Returns: true 면 accept, false 면 drop.
    private func shouldAcceptInlineData(size: Int, itemIndex: Int, reprIndex: Int) -> Bool {
        let spec = ClipboardLimits.maxInlineDataBytes

        if size <= spec { return true }

        let warn = ClipboardLimits.inlineDataWarnThreshold
        if size > warn {
            logger.error("Item \(itemIndex)[\(reprIndex)] has inline data \(size) bytes, significantly exceeding spec limit \(spec) bytes — dropping representation (spec requires omitted flag for data > 128 KiB)")
            return false
        }

        logger.warning("Item \(itemIndex)[\(reprIndex)] has inline data \(size) bytes, slightly exceeding spec limit \(spec) bytes — accepting (likely sender bug; spec requires omitted flag for data > 128 KiB)")
        return true
    }

    /// hard threshold 위반 등 fatal 한 spec 위반을 감지했을 때 세션을 종료시킵니다.
    /// `NoctilucaClient` 에 도달하면 `remoteFault` 로 uiEvents + Goodbye 시퀀스를 트리거합니다.
    private func escalateFatalClose(reason: String) async {
        guard let session = self.clientSession,
              let noctilucaClient = session.delegate as? NoctilucaClient else {
            logger.warning("escalateFatalClose: NoctilucaClient not reachable, falling back to local logging only")
            return
        }
        await noctilucaClient.remoteFault(notice: .protocolViolation, reason: reason)
    }

    // MARK: - Remote Items Resolve & Apply

    /// 원격에서 수신한 클립보드 아이템을 resolve(omitted data 다운로드)하고 로컬 클립보드에 적용합니다.
    private func resolveAndApplyRemoteItems(_ items: [ClipboardItem], allowFile: Bool) {
        if let reason = self.detectHardViolation(items) {
            logger.error(reason)
            Task { [weak self] in
                await self?.escalateFatalClose(reason: reason)
            }
            return
        }

        let limitedItems = self.truncateItemsToSpec(items)

        Task {
            await state.resolveTask?.cancel()

            let task = Task { [weak self] in
                guard let self = self else { return }

                var resolvedItems: [ClipboardItem] = []
                var fileTransferItems: [(Int, FileTransferMetadata)] = []

                for (itemIndex, item) in limitedItems.enumerated() {
                    let representations = self.truncateRepresentationsToSpec(item.representations, itemIndex: itemIndex)

                    // 파일 전송 아이템인지 체크
                    if let fileRepr = representations.first(where: {
                        $0.contentType == FileTransferContentType.fileTransfer
                    }),
                       let data = fileRepr.data,
                       let metadata = try? JSONDecoder().decode(FileTransferMetadata.self, from: data) {
                        fileTransferItems.append((itemIndex, metadata))
                        continue
                    }

                    // 일반 아이템: omitted resolve 로직
                    var resolvedRepresentations: [ClipboardData] = []

                    for (reprIndex, representation) in representations.enumerated() {
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
                        } else if let inlineData = representation.data {
                            guard self.shouldAcceptInlineData(size: inlineData.count, itemIndex: itemIndex, reprIndex: reprIndex) else {
                                continue
                            }
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

        if let transferError = channel.transferError {
            logger.warning("Omitted data transfer failed (item=\(itemIndex), repr=\(reprIndex)): \(transferError)")
            return nil
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

        await state.storeSnapshot(ClipboardDataSnapshot())
        await state.storeFileTransferSnapshot(FileTransferSnapshot())
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

