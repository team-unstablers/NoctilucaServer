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
///   5) realpath 기반 mount root containment 사후 검증 — 중간/leaf 컴포넌트가
///      symlink 라서 lexical 검증을 우회한 경우를 차단. mdproto §"Symlinks"
///      가 명령하는 "outside-the-subtree symlink MUST NOT be followed" 를
///      강제하기 위함.
///
/// 실제 syscall 시점의 race (TOCTOU) 는 호출자가 `O_NOFOLLOW_ANY` (macOS 11+) 등
/// 으로 함께 방어해야 합니다 — 본 validator 는 lexical + realpath 사전 검증만
/// 보장합니다.
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
        let resolved = url.standardizedFileURL

        // 5) realpath 기반 사후 검증 — mdproto §"Symlinks" 의 "outside-the-subtree
        //    symlink MUST NOT be followed" 강제. 중간 component 가 symlink 라
        //    lexical 정규화로 못 잡는 escape 를 차단한다.
        try checkSymlinkContainment(resolved: resolved, mountRoot: mountRoot)
        return resolved
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

    /// `resolved` 의 realpath 가 `mountRoot` 의 realpath subtree 안에 있는지
    /// 검사. `URL.resolvingSymlinksInPath()` 는 존재하는 component 의 symlink 만
    /// 따라가고 비존재 component 는 그대로 두므로:
    ///  - 정상 경로 → resolved 는 mountRoot subtree 그대로 유지 → pass.
    ///  - 중간 component 가 외부로 나가는 symlink → 그 부분이 follow 되어
    ///    canonical resolved 가 mountRoot prefix 를 잃음 → fail.
    ///  - mkdir / createNew 같은 비존재 leaf 도 OK — 비존재 component 는 그대로
    ///    두기에 prefix 가 보존된다.
    ///
    /// 즉 `isWithin` 이 정의하는 동일한 prefix 검증을 사후검증으로 재사용한다.
    private static func checkSymlinkContainment(resolved: URL, mountRoot: URL) throws {
        if !isWithin(resolved, root: mountRoot) {
            throw ValidationError.escapesRoot(component: "<symlink>")
        }
    }
}
