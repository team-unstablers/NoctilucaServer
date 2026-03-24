//
//  ClipboardWatcher.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//

import Foundation

import Cocoa

import SiriusKit
import UniformTypeIdentifiers

// MARK: - MIME <-> PasteboardType Mapping

private enum ClipboardMIMEMapping {
    static let mappings: [(mime: String, type: NSPasteboard.PasteboardType)] = [
        ("text/plain",    .string),
        ("text/html",     .html),
        ("text/rtf",      .rtf),
        ("image/png",     .png),
        ("image/tiff",    .tiff),
        ("application/pdf", NSPasteboard.PasteboardType("com.adobe.pdf")),
        ("application/x-file-url", .fileURL),
    ]

    static let typeToMime: [NSPasteboard.PasteboardType: String] = {
        Dictionary(mappings.map { ($0.type, $0.mime) }, uniquingKeysWith: { first, _ in first })
    }()

    static let mimeToType: [String: NSPasteboard.PasteboardType] = {
        Dictionary(mappings.map { ($0.mime, $0.type) }, uniquingKeysWith: { first, _ in first })
    }()

    static func mimeType(for pasteboardType: NSPasteboard.PasteboardType) -> String {
        if let mime = typeToMime[pasteboardType] {
            return mime
        }
        return "application/x-\(pasteboardType.rawValue)"
    }

    static func pasteboardType(for mime: String) -> NSPasteboard.PasteboardType {
        if let type = mimeToType[mime] {
            return type
        }
        // application/x- 접두사 제거하여 UTI 복원
        if mime.hasPrefix("application/x-") {
            let uti = String(mime.dropFirst("application/x-".count))
            return NSPasteboard.PasteboardType(uti)
        }
        return NSPasteboard.PasteboardType(mime)
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
    static let omitThreshold: UInt64 = 2048 * 1024

    private init() {}

    /// NSPasteboard.general의 현재 내용을 [ClipboardItem]으로 변환합니다.
    func current() -> [ClipboardItem] {
        let pasteboard = NSPasteboard.general
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return []
        }

        let settings = SettingsStore.shared.settings.clipboard

        var items: [ClipboardItem] = []

        for pasteboardItem in pasteboardItems {
            var representations: [ClipboardData] = []

            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else {
                    continue
                }

                let mime = ClipboardMIMEMapping.mimeType(for: type)
#if DEBUG
                logger.info("[DUMP] type: \(type.rawValue) => mime: \(mime), size: \(data.count) bytes")
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

    /// NSPasteboard.general의 현재 내용을 [ClipboardItem]과 omitted 데이터 스냅샷으로 변환합니다.
    func currentWithSnapshot() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return ClipboardSnapshot(items: [], omittedData: ClipboardDataSnapshot(), fileTransferData: FileTransferSnapshot())
        }

        let settings = SettingsStore.shared.settings.clipboard

        var items: [ClipboardItem] = []
        var omittedData = ClipboardDataSnapshot()
        var fileTransferData = FileTransferSnapshot()
        var itemIndex = 0

        for pasteboardItem in pasteboardItems {
            // fileURL 타입을 포함하는 아이템은 파일 전송으로 처리
            if pasteboardItem.types.contains(.fileURL),
               let urlData = pasteboardItem.data(forType: .fileURL),
               let urlString = String(data: urlData, encoding: .utf8),
               let url = URL(string: urlString),
               url.isFileURL,
               let metadata = FileTransferMetadata.from(fileURL: url) {

                let jsonData = try! JSONEncoder().encode(metadata)
                let representation = ClipboardData(
                    contentType: FileTransferContentType.fileTransfer,
                    size: metadata.size,
                    data: jsonData,
                    flags: []
                )
                items.append(ClipboardItem(representations: [representation]))
                fileTransferData.store(itemIndex: itemIndex, metadata: metadata)
                itemIndex += 1
                continue
            }

            // 일반 아이템 처리
            var representations: [ClipboardData] = []
            var reprIndex = 0

            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else {
                    continue
                }

                let mime = ClipboardMIMEMapping.mimeType(for: type)
#if DEBUG
                logger.info("[DUMP] type: \(type.rawValue) => mime: \(mime), size: \(data.count) bytes")
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

    /// 수신된 ClipboardItem 배열을 NSPasteboard.general에 씁니다.
    func set(items: [ClipboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var pasteboardItems: [NSPasteboardItem] = []

        for item in items {
            let pasteboardItem = NSPasteboardItem()

            for representation in item.representations {
                // omitted 데이터는 스킵
                guard !representation.flags.contains(.omitted),
                      let data = representation.data else {
                    continue
                }

                let type = ClipboardMIMEMapping.pasteboardType(for: representation.contentType)
                pasteboardItem.setData(data, forType: type)
            }

            pasteboardItems.append(pasteboardItem)
        }

        pasteboard.writeObjects(pasteboardItems)

        // Self-change 억제: 쓰기 후 현재 changeCount를 watcher에 기록
        ClipboardWatcher.shared.suppressedChangeCount = pasteboard.changeCount
    }

    /// 수신된 ClipboardItem과 파일 전송 promise를 함께 NSPasteboard.general에 씁니다.
    func setWithFileTransfer(
        items: [ClipboardItem],
        fileTransferItems: [(Int, FileTransferMetadata)],
        coordinator: FileTransferCoordinator
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var pasteboardObjects: [NSPasteboardWriting] = []

        // 일반 아이템
        for item in items {
            let pasteboardItem = NSPasteboardItem()

            for representation in item.representations {
                guard !representation.flags.contains(.omitted),
                      let data = representation.data else {
                    continue
                }

                let type = ClipboardMIMEMapping.pasteboardType(for: representation.contentType)
                pasteboardItem.setData(data, forType: type)
            }

            pasteboardObjects.append(pasteboardItem)
        }

        // 파일 전송 promise
        for (_, metadata) in fileTransferItems {
            let utType: String
            if metadata.isDirectory {
                utType = UTType.folder.identifier
            } else {
                utType = (UTType(mimeType: metadata.contentType) ?? .data).identifier
            }

            let provider = NSFilePromiseProvider(fileType: utType, delegate: coordinator)
            provider.userInfo = metadata
            pasteboardObjects.append(provider)
        }

        pasteboard.writeObjects(pasteboardObjects)
        ClipboardWatcher.shared.suppressedChangeCount = pasteboard.changeCount
    }

    /// 설정에 따라 해당 contentType을 포함할지 결정합니다.
    private func shouldInclude(contentType: String, settings: AppSettings.Clipboard) -> Bool {
        if settings.textOnly {
            return contentType.hasPrefix("text/")
        }

        if !settings.allowImage && contentType.hasPrefix("image/") {
            return false
        }

        if !settings.allowRichText && (contentType == "text/html" || contentType == "text/rtf") {
            return false
        }

        if !settings.allowFile && contentType == "application/x-file-url" {
            return false
        }

        if !settings.allowUnknownFormat && !ClipboardMIMEMapping.isKnownFormat(contentType) {
            return false
        }

        return true
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

    private init() {}

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

    // MARK: - Polling

    private func startWatching() {
        guard timer == nil else { return }

        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }

        logger.info("Clipboard watching started (interval=\(self.pollInterval)s)")
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil

        logger.info("Clipboard watching stopped")
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Self-change 억제
        if let suppressed = suppressedChangeCount, currentCount == suppressed {
            suppressedChangeCount = nil
            logger.debug("Self-change suppressed (changeCount=\(currentCount))")
            return
        }

        let snapshot = manager.currentWithSnapshot()
        guard !snapshot.items.isEmpty else { return }

        notifySubscribers(snapshot: snapshot)
    }

    private func notifySubscribers(snapshot: ClipboardSnapshot) {
        // 죽은 weak ref 정리
        subscribers = subscribers.filter { $0.value.value != nil }

        for (_, ref) in subscribers {
            ref.value?.notifyChange(snapshot: snapshot)
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
