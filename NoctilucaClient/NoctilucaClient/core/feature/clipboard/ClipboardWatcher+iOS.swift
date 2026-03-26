//
//  ClipboardWatcher.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//

#if os(iOS)
import Foundation

import UIKit
import UniformTypeIdentifiers

import SiriusKitClient

// MARK: - MIME <-> PasteboardType Mapping

private enum ClipboardMIMEMapping {
    static let mappings: [(mime: String, type: UTType)] = [
        ("text/plain",    .plainText),
        ("text/plain;charset=utf-8", .plainText),
        ("text/html",     .html),
        ("text/rtf",      .rtf),
        ("image/png",     .png),
        ("image/tiff",    .tiff),
        ("application/pdf", .pdf),
        ("application/x-file-url", .fileURL),
    ]

    static let typeToMime: [UTType: String] = {
        Dictionary(mappings.map { ($0.type, $0.mime) }, uniquingKeysWith: { first, _ in first })
    }()

    static let mimeToType: [String: UTType] = {
        Dictionary(mappings.map { ($0.mime, $0.type) }, uniquingKeysWith: { first, _ in first })
    }()

    static func mimeType(for utType: UTType) -> String {
        if let mime = typeToMime[utType] {
            return mime
        }
        return utType.preferredMIMEType ?? "application/x-\(utType.identifier)"
    }

    /// UTI 문자열(UIPasteboard의 key)로부터 MIME 타입을 반환합니다.
    static func mimeType(forUTI utiString: String) -> String {
        if let utType = UTType(utiString) {
            return mimeType(for: utType)
        }
        return "application/x-\(utiString)"
    }

    static func pasteboardType(for mime: String) -> UTType {
        if let type = mimeToType[mime] {
            return type
        }

        // application/x- 접두사 제거하여 UTI 복원
        if mime.hasPrefix("application/x-") {
            let uti = String(mime.dropFirst("application/x-".count))
            if let type = UTType(uti) {
                return type
            }
        }

        return UTType(mimeType: mime) ?? .data
    }

    /// 알려진 형식인지 판단
    static func isKnownFormat(_ contentType: String) -> Bool {
        return contentType.hasPrefix("text/") ||
               contentType.hasPrefix("image/") ||
               contentType == "application/pdf" ||
               contentType == "application/x-file-url"
    }
}

// MARK: - ClipboardDataSnapshot

/// omitted 처리된 representation의 실제 데이터를 보관하는 스냅샷
struct ClipboardDataSnapshot {
    private var storage: [String: Data] = [:]

    mutating func store(itemIndex: Int, reprIndex: Int, data: Data) {
        storage["\(itemIndex):\(reprIndex)"] = data
    }

    func get(itemIndex: Int, reprIndex: Int) -> Data? {
        return storage["\(itemIndex):\(reprIndex)"]
    }

    var isEmpty: Bool { storage.isEmpty }
}

/// ClipboardManager.currentWithSnapshot()의 반환 타입
struct ClipboardSnapshot {
    let items: [ClipboardItem]
    let omittedData: ClipboardDataSnapshot
    let fileTransferData: FileTransferSnapshot
}

// MARK: - ClipboardManager

@MainActor
class ClipboardManager {
    static let shared = ClipboardManager()

    private let logger = NoctilucaLogger(category: "ClipboardManager")

    /// 128KB 임계값 - 이 크기를 초과하는 representation은 omitted 처리
    static let omitThreshold: UInt64 = 128 * 1024

    private init() {}


    /// UIPasteboard.general의 현재 내용을 [ClipboardItem]으로 변환합니다.
    func current(settings: SessionSettings.Clipboard) -> [ClipboardItem] {
        let pasteboard = UIPasteboard.general
        let pasteboardItems = pasteboard.items

        var items: [ClipboardItem] = []

        for pasteboardItem in pasteboardItems {
            var representations: [ClipboardData] = []

            for (utiString, object) in pasteboardItem {
                guard let data = Self.coerceToData(object) else {
                    continue
                }

                let mime = ClipboardMIMEMapping.mimeType(forUTI: utiString)

#if DEBUG
                logger.info("[DUMP] type: \(utiString) => mime: \(mime), size: \(data.count) bytes")
#endif

                guard shouldInclude(contentType: mime, settings: settings) else {
                    continue
                }

                let size = UInt64(data.count)

                if size > Self.omitThreshold {
                    representations.append(ClipboardData(
                        contentType: mime,
                        size: size,
                        data: nil,
                        flags: .omitted
                    ))
                } else {
                    representations.append(ClipboardData(
                        contentType: mime,
                        size: size,
                        data: data,
                        flags: []
                    ))
                }
            }

            if !representations.isEmpty {
                items.append(ClipboardItem(representations: representations))
            }
        }

        return items
    }

    /// UIPasteboard.general의 현재 내용을 [ClipboardItem]과 omitted 데이터 스냅샷으로 변환합니다.
    func currentWithSnapshot(settings: SessionSettings.Clipboard) -> ClipboardSnapshot {
        let pasteboard = UIPasteboard.general
        let pasteboardItems = pasteboard.items

        var items: [ClipboardItem] = []
        var omittedData = ClipboardDataSnapshot()
        var fileTransferData = FileTransferSnapshot()
        var itemIndex = 0

        for pasteboardItem in pasteboardItems {
            var representations: [ClipboardData] = []
            var reprIndex = 0

            for (utiString, object) in pasteboardItem {
                guard let data = Self.coerceToData(object) else {
                    continue
                }

                let mime = ClipboardMIMEMapping.mimeType(forUTI: utiString)
#if DEBUG
                logger.info("[DUMP] type: \(utiString) => mime: \(mime), size: \(data.count) bytes")
#endif

                guard shouldInclude(contentType: mime, settings: settings) else {
                    continue
                }

                let size = UInt64(data.count)

                if size > Self.omitThreshold {
                    representations.append(ClipboardData(
                        contentType: mime,
                        size: size,
                        data: nil,
                        flags: .omitted
                    ))
                    omittedData.store(itemIndex: itemIndex, reprIndex: reprIndex, data: data)
                } else {
                    representations.append(ClipboardData(
                        contentType: mime,
                        size: size,
                        data: data,
                        flags: []
                    ))
                }

                reprIndex += 1
            }

            if !representations.isEmpty {
                items.append(ClipboardItem(representations: representations))
            }

            itemIndex += 1
        }

        return ClipboardSnapshot(items: items, omittedData: omittedData, fileTransferData: fileTransferData)
    }

    /// 수신된 ClipboardItem 배열을 UIPasteboard.general에 씁니다.
    func set(items: [ClipboardItem]) {
        let pasteboard = UIPasteboard.general

        var pasteboardItems: [[String: Any]] = []

        for item in items {
            var pasteboardItem: [String: Any] = [:]

            for representation in item.representations {
                // omitted 데이터는 스킵
                guard !representation.flags.contains(.omitted),
                      let data = representation.data else {
                    continue
                }

                let utType = ClipboardMIMEMapping.pasteboardType(for: representation.contentType)
                pasteboardItem[utType.identifier] = data
            }

            if !pasteboardItem.isEmpty {
                pasteboardItems.append(pasteboardItem)
            }
        }

        pasteboard.items = pasteboardItems

        // Self-change 억제: 쓰기 후 현재 changeCount를 watcher에 기록
        ClipboardWatcher.shared.suppressedChangeCount = pasteboard.changeCount
    }

    /// 수신된 ClipboardItem과 파일 전송 ItemProvider를 함께 UIPasteboard.general에 씁니다.
    /// 파일은 미리 다운로드한 뒤, NSItemProvider는 다운로드 완료된 URL만 반환한다.
    func setWithFileTransfer(
        items: [ClipboardItem],
        fileTransferItems: [(Int, FileTransferMetadata)],
        coordinator: FileTransferCoordinator
    ) async {
        let pasteboard = UIPasteboard.general

        // 일반 아이템
        var pasteboardItems: [[String: Any]] = []

        for item in items {
            var pasteboardItem: [String: Any] = [:]

            for representation in item.representations {
                guard !representation.flags.contains(.omitted),
                      let data = representation.data else {
                    continue
                }

                let utType = ClipboardMIMEMapping.pasteboardType(for: representation.contentType)
                pasteboardItem[utType.identifier] = data
            }

            if !pasteboardItem.isEmpty {
                pasteboardItems.append(pasteboardItem)
            }
        }

        // 파일을 미리 다운로드한 뒤 NSItemProvider 생성
        var itemProviders: [NSItemProvider] = []
        for (_, metadata) in fileTransferItems {
            do {
                let fileURL = try await coordinator.predownloadFile(metadata: metadata)
                let itemProvider = coordinator.createItemProvider(for: metadata, fileURL: fileURL)
                itemProviders.append(itemProvider)
            } catch {
                logger.error("Failed to pre-download file \(metadata.name): \(error)")
            }
        }

        if !itemProviders.isEmpty {
            pasteboard.items = pasteboardItems
            pasteboard.setItemProviders(
                itemProviders,
                localOnly: true,
                expirationDate: nil
            )
        } else {
            pasteboard.items = pasteboardItems
        }

        ClipboardWatcher.shared.suppressedChangeCount = pasteboard.changeCount
    }

    // MARK: - Private Helpers

    /// 설정에 따라 해당 contentType을 포함할지 결정합니다.
    private func shouldInclude(contentType: String, settings: SessionSettings.Clipboard) -> Bool {
        if settings.textOnly {
            return contentType.hasPrefix("text/")
        }

        if !settings.allowFile && (contentType == "application/x-file-url" || contentType == FileTransferContentType.fileTransfer) {
            return false
        }

        return true
    }

    /// UIPasteboard의 Any 값을 Data로 변환합니다.
    private static func coerceToData(_ object: Any) -> Data? {
        if let data = object as? Data {
            return data
        }
        if let string = object as? String {
            return Data(string.utf8)
        }
        if let url = object as? URL {
            return Data(url.absoluteString.utf8)
        }
        if let image = object as? UIImage {
            return image.pngData()
        }
        return nil
    }
}

// MARK: - ClipboardWatcher

@MainActor
class ClipboardWatcher {
    static let shared = ClipboardWatcher()

    var pollInterval: TimeInterval = 1.0

    private let logger = NoctilucaLogger(category: "ClipboardWatcher")
    private let manager = ClipboardManager.shared

    private var timer: Timer?
    private var lastChangeCount: Int = 0

    /// ClipboardManager.set()이 갱신한 changeCount. self-change 억제에 사용.
    var suppressedChangeCount: Int?

    private var subscribers: [UUID: WeakSubscriberRef] = [:]

    private init() {
        // 앱 라이프사이클 노티피케이션 등록
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidEnterBackground()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidBecomeActive()
            }
        }
    }

    func addSubscriber(_ subscription: ClipboardSubscription) {
        subscribers[subscription.id] = WeakSubscriberRef(subscription)

        if subscribers.count == 1 {
            startWatching()
        }

        logger.info("Subscriber added (id=\(subscription.id)), total=\(self.subscribers.count)")
    }

    func removeSubscriber(_ subscription: ClipboardSubscription) {
        removeSubscriberById(subscription.id)
    }

    func removeSubscriberById(_ id: UUID) {
        subscribers.removeValue(forKey: id)

        if subscribers.isEmpty {
            stopWatching()
        }

        logger.info("Subscriber removed (id=\(id)), total=\(self.subscribers.count)")
    }

    // MARK: - App Lifecycle

    private func handleAppDidEnterBackground() {
        guard !subscribers.isEmpty else { return }
        pauseTimer()
        logger.info("Clipboard watching paused (app entered background)")
    }

    private func handleAppDidBecomeActive() {
        guard !subscribers.isEmpty else { return }
        // 포그라운드 복귀 시 즉시 클립보드 변경 확인
        checkClipboard()
        resumeTimer()
        logger.info("Clipboard watching resumed (app became active)")
    }

    // MARK: - Polling

    private func startWatching() {
        lastChangeCount = UIPasteboard.general.changeCount
        resumeTimer()

        logger.info("Clipboard watching started (interval=\(self.pollInterval)s)")
    }

    private func stopWatching() {
        pauseTimer()

        logger.info("Clipboard watching stopped")
    }

    private func resumeTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let currentCount = UIPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Self-change 억제
        if let suppressed = suppressedChangeCount, currentCount == suppressed {
            suppressedChangeCount = nil
            logger.debug("Self-change suppressed (changeCount=\(currentCount))")
            return
        }

        notifySubscribers()
    }

    private func notifySubscribers() {
        // 죽은 weak ref 정리
        subscribers = subscribers.filter { $0.value.value != nil }

        for (_, ref) in subscribers {
            ref.value?.notifyChange()
        }
    }
}

// MARK: - WeakSubscriberRef

private struct WeakSubscriberRef {
    weak var value: ClipboardSubscription?

    init(_ value: ClipboardSubscription) {
        self.value = value
    }
}
#endif
