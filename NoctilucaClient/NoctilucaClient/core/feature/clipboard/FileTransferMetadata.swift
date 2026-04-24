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
    /// 원본 파일 시스템 경로 (예: "/Users/foo/test.mp3")
    let path: String
    /// 파일 크기 (바이트). 디렉토리의 경우 0
    let size: UInt64
    /// MIME 타입. 디렉토리는 "application/x-noc-directory"
    let contentType: String

    var isDirectory: Bool {
        contentType == FileTransferContentType.directory
    }
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
    private var entries: [Int: FileTransferMetadata] = [:]

    mutating func store(itemIndex: Int, metadata: FileTransferMetadata) {
        entries[itemIndex] = metadata
    }

    func get(itemIndex: Int) -> FileTransferMetadata? {
        entries[itemIndex]
    }

    /// 요청된 경로가 이 스냅샷의 파일이거나 디렉토리의 하위 경로인지 검증하고,
    /// 통과 시 정규화된 URL(심볼릭 링크 해석 + `..` 축약)을 반환합니다. 실패 시 nil.
    ///
    /// 호출자는 반환된 URL을 이후의 파일 I/O(`FileHandle`, `writeFromFile`, `fileExists` 등)에
    /// 그대로 사용해야 합니다. 원본 입력 문자열을 재사용하면 TOCTOU / path traversal 우회가
    /// 가능합니다.
    func validatePath(_ path: String) -> URL? {
        let requested = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let requestedPath = requested.path

        for metadata in entries.values {
            let root = URL(fileURLWithPath: metadata.path).standardizedFileURL.resolvingSymlinksInPath()
            let rootPath = root.path

            if requestedPath == rootPath {
                return requested
            }
            if metadata.isDirectory {
                let dirPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                if requestedPath.hasPrefix(dirPrefix) {
                    return requested
                }
            }
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

extension FileTransferMetadata {
    /// 파일 URL에서 FileTransferMetadata를 생성합니다.
    static func from(fileURL url: URL) -> FileTransferMetadata? {
        let fm = FileManager.default
        let filePath = url.path
        var isDirectory: ObjCBool = false

        guard fm.fileExists(atPath: filePath, isDirectory: &isDirectory) else {
            return nil
        }

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

        return FileTransferMetadata(
            name: url.lastPathComponent,
            path: filePath,
            size: fileSize,
            contentType: mimeType
        )
    }
}
