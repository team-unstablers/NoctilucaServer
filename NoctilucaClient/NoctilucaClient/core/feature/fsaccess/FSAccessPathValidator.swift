//
//  FSAccessPathValidator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import Foundation

import SiriusKitClient

/// `fsaccess_mount.mdproto.md` 의 PATH HANDLING 파이프라인을 구현합니다.
///
///   1) UTF-8 / NUL 바이트 검증
///   2) `/` split → empty / `.` drop, `..` resolve (mount root 밖으로 못 나감)
///   3) 길이 체크 (spec=4096, warn=6144, hard=65536)
///   4) host path 결합
///   5) (호출자가 심볼릭 링크 follow 한 경우) subtree 재검사
enum FSAccessPathValidator {
    /// 정상 경로 길이 상한 (Pattern A spec).
    static let pathSpecLimit = 4096
    /// warn 임계값 (Pattern A 1.5x).
    static let pathWarnLimit = 6 * 1024
    /// hard 임계값 — 이 값을 넘으면 채널을 닫아야 합니다.
    static let pathHardLimit = 64 * 1024

    enum ValidationError: Error, CustomStringConvertible {
        case notUTF8
        case containsNUL
        case escapesRoot(component: String)
        case pathTooLong(observed: Int, limit: Int)
        case pathTooLongHard(observed: Int, limit: Int)

        var description: String {
            switch self {
            case .notUTF8:
                return "Path is not valid UTF-8"
            case .containsNUL:
                return "Path contains NUL byte"
            case .escapesRoot(let component):
                return "Path escapes mount root via component '\(component)'"
            case .pathTooLong(let observed, let limit):
                return "Path length \(observed) exceeds soft limit \(limit)"
            case .pathTooLongHard(let observed, let limit):
                return "Path length \(observed) exceeds hard limit \(limit)"
            }
        }

        var fileSystemErrorCode: FileSystemErrorCode {
            switch self {
            case .notUTF8, .containsNUL, .escapesRoot:
                return .invalidPath
            case .pathTooLong, .pathTooLongHard:
                return .pathTooLong
            }
        }
    }

    /// path 를 mount root 기준으로 정규화하고 host URL 을 반환합니다.
    ///
    /// - Parameters:
    ///   - path: wire 에서 들어온 path 문자열
    ///   - mountRoot: 이 mount session 의 host root URL (이미 절대 경로 + symlink 해석 완료)
    /// - Returns: host filesystem 의 절대 URL
    /// - Throws: `ValidationError`
    static func resolve(path: String, mountRoot: URL) throws -> URL {
        // 1) NUL 검증
        if path.utf8.contains(0) {
            throw ValidationError.containsNUL
        }

        // 2) 길이 검증 (UTF-8 byte length 기준)
        let byteLength = path.utf8.count
        if byteLength > pathHardLimit {
            throw ValidationError.pathTooLongHard(observed: byteLength, limit: pathHardLimit)
        }
        if byteLength > pathSpecLimit {
            throw ValidationError.pathTooLong(observed: byteLength, limit: pathSpecLimit)
        }

        // 3) 정규화
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [String] = []
        for component in components {
            let str = String(component)
            if str == "." {
                continue
            }
            if str == ".." {
                if stack.isEmpty {
                    throw ValidationError.escapesRoot(component: "..")
                }
                stack.removeLast()
                continue
            }
            stack.append(str)
        }

        // 4) host path 조립
        var url = mountRoot
        for component in stack {
            url.appendPathComponent(component)
        }
        return url.standardizedFileURL
    }

    /// `resolved` URL 이 `mountRoot` 의 subtree 에 속하는지 재검사합니다.
    /// 심볼릭 링크 follow 후 escape 여부를 확인할 때 사용합니다.
    static func isWithin(_ resolved: URL, root mountRoot: URL) -> Bool {
        let rootPath = mountRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedPath = resolved.standardizedFileURL.resolvingSymlinksInPath().path

        // 정확히 root 자체이거나 root 의 subdirectory 인지 검사 (prefix + 경로 구분자)
        if resolvedPath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return resolvedPath.hasPrefix(prefix)
    }
}
