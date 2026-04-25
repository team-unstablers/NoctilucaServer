//
//  FileTransferMetadata.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/24/26.
//

import Foundation

import UniformTypeIdentifiers

// MARK: - Content Type Constants

enum FileTransferContentType {
    /// 파일 전송 메타데이터를 나타내는 content type
    static let fileTransfer = "application/x-noc-file-transfer"
    /// 디렉토리를 나타내는 content type
    static let directory = "application/x-noc-directory"
}

// MARK: - Safe Path Component

extension String {
    /// 원격에서 수신한 문자열이 경로 이탈(`/`, `..`, null byte 등) 위험이 없는 단일
    /// path component인지 검증한다.
    var isSafePathComponent: Bool {
        guard !isEmpty else { return false }
        guard self != "." && self != ".." else { return false }
        guard !contains("/") else { return false }
        guard !contains("\0") else { return false }
        if contains("..") {
            let comps = split(separator: "/", omittingEmptySubsequences: false)
            if comps.contains(where: { $0 == ".." }) { return false }
        }
        return true
    }
}

// MARK: - FileTransferMetadata

/// 클립보드를 통해 전송되는 파일 메타데이터 (ClipboardData.data에 JSON으로 직렬화)
struct FileTransferMetadata: Codable {
    /// 파일/디렉토리 이름 (예: "test.mp3")
    let name: String
    /// Sirius 프로토콜로 노출하기 위한 가상 경로 (예: "/noctiluca/clipboard/file/(UUID4)")
    let path: String
    /// 파일 크기 (바이트). 디렉토리의 경우 0
    let size: UInt64
    /// MIME 타입. 디렉토리는 "application/x-noc-directory"
    let contentType: String

    var isDirectory: Bool {
        contentType == FileTransferContentType.directory
    }
}

struct FileTransferMetadataPrivate {
    let metadata: FileTransferMetadata

    let virtualPath: String
    let realPath: String
}

// MARK: - DirectoryEntry

/// TransferChannel을 통해 전송되는 디렉토리 리스팅의 개별 항목
struct DirectoryEntry: Codable {
    let name: String
    let contentType: String
    let size: UInt64

    var isDirectory: Bool {
        contentType == FileTransferContentType.directory
    }

    /// 원격에서 수신한 name이 안전한 단일 path component인지 검증한다.
    /// 수신 측이 `parent.path + "/" + entry.name` 으로 재귀 경로를 만들기 전에
    /// 반드시 호출되어야 한다.
    var hasSafeName: Bool { name.isSafePathComponent }
}

// MARK: - FileTransferSnapshot

/// 클립보드에 복사된 파일들의 경로를 보관하는 스냅샷
/// ClipboardDataSnapshot과 유사하지만, Data 대신 파일 메타데이터를 저장한다.
/// 보안 검증(요청된 경로가 실제 복사된 파일인지 확인)에도 사용된다.
struct FileTransferSnapshot {
    private var entries: [Int: FileTransferMetadataPrivate] = [:]

    mutating func store(itemIndex: Int, metadata: FileTransferMetadataPrivate) {
        entries[itemIndex] = metadata
    }

    func get(itemIndex: Int) -> FileTransferMetadataPrivate? {
        entries[itemIndex]
    }

    /// 요청된 가상 경로가 이 스냅샷의 파일/디렉토리이거나 그 디렉토리의 하위 가상 경로인지
    /// 검증하고, 통과 시 매핑된 실제 파일의 정규화된 URL(심볼릭 링크 해석 + `..` 축약)을 반환합니다.
    /// 실패 시 nil.
    ///
    /// 호출자는 반환된 URL을 이후의 파일 I/O(`FileHandle`, `writeFromFile`, `fileExists` 등)에
    /// 그대로 사용해야 합니다. 원본 입력 문자열을 재사용하면 TOCTOU / path traversal 우회가
    /// 가능합니다.
    func validatePath(_ path: String) -> URL? {
        for entry in entries.values {
            let virtualPath = entry.virtualPath
            let realRoot = URL(fileURLWithPath: entry.realPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()

            // 1) 가상 경로 정확 일치 → root의 실제 경로 반환
            if path == virtualPath {
                return realRoot
            }

            // 2) 디렉토리 entry의 하위 가상 경로 → 상대 경로를 실제 경로에 결합
            guard entry.metadata.isDirectory else { continue }

            let prefix = virtualPath.hasSuffix("/") ? virtualPath : virtualPath + "/"
            guard path.hasPrefix(prefix) else { continue }

            let relative = String(path.dropFirst(prefix.count))
            let components = relative.split(separator: "/", omittingEmptySubsequences: false)
                .map(String.init)

            // 각 컴포넌트가 안전한 단일 path component인지 확인
            // (빈 문자열, `.`, `..`, null byte, 추가 `/` 거부)
            guard !components.isEmpty,
                  components.allSatisfy({ $0.isSafePathComponent }) else {
                return nil
            }

            let candidate = components.reduce(realRoot) { $0.appendingPathComponent($1) }
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()

            // 정규화 후에도 root 디렉토리 안에 있는지 재확인 (심볼릭 링크/`..` 우회 방지)
            let rootPath = realRoot.path
            let rootPathWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if resolved.path == rootPath || resolved.path.hasPrefix(rootPathWithSlash) {
                return resolved
            }
            return nil
        }

        return nil
    }

    var isEmpty: Bool { entries.isEmpty }
}

// MARK: - FileTransferError

enum FileTransferError: Error, CustomStringConvertible {
    case sessionUnavailable
    case channelOpenFailed
    case noDataStream
    case fileNotFound(path: String)
    case pathValidationFailed(path: String)
    case directoryListingFailed

    var description: String {
        switch self {
        case .sessionUnavailable:
            return "Session is unavailable"
        case .channelOpenFailed:
            return "Failed to open transfer channel"
        case .noDataStream:
            return "No data stream available on transfer channel"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .pathValidationFailed(let path):
            return "Path validation failed: \(path)"
        case .directoryListingFailed:
            return "Failed to list directory contents"
        }
    }
}

// MARK: - FileTransferMetadata Utilities

extension FileTransferMetadataPrivate {
    /// 파일 URL에서 FileTransferMetadataPrivate를 생성합니다.
    static func from(fileURL url: URL) -> FileTransferMetadataPrivate? {
        let fm = FileManager.default
        let filePath = url.path
        var isDirectory: ObjCBool = false

        guard fm.fileExists(atPath: filePath, isDirectory: &isDirectory) else {
            return nil
        }

        let virtualPath = "/noctiluca/clipboard/file/\(UUID().uuidString)"

        let fileSize: UInt64
        let mimeType: String

        if isDirectory.boolValue {
            fileSize = 0
            mimeType = FileTransferContentType.directory
        } else {
            let attrs = try? fm.attributesOfItem(atPath: filePath)
            fileSize = (attrs?[.size] as? UInt64) ?? 0
            mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }

        let metadata = FileTransferMetadata(
            name: url.lastPathComponent,
            path: virtualPath,
            size: fileSize,
            contentType: mimeType
        )

        return FileTransferMetadataPrivate(
            metadata: metadata,
            virtualPath: virtualPath,
            realPath: filePath
        )
    }
}
