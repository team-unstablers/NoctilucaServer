//
//  FSAccessAppleDoubleFilter.swift
//  NoctilucaClient
//
//  macOS 의 NFS client (consuming peer) 가 비-HFS 볼륨에서 만들어대는
//  AppleDouble sidecar (`._<name>`) 를 식별하기 위한 작은 path 매처.
//  navigator (이 client) 가 `AppSettings.FileAccess.hideAppleDoubleFiles`
//  토글을 통해 자기 책임으로 sidecar 를 흡수하도록 한다.
//

import Foundation

enum FSAccessAppleDoubleFilter {
    /// 주어진 leaf name 이 AppleDouble sidecar 인지 검사.
    /// 일반 파일 / 디렉토리 등 leaf 형태와 무관하게 prefix 만 본다.
    static func isSidecarName(_ name: String) -> Bool {
        return name.hasPrefix("._")
    }

    /// path 의 마지막 component 만 추출해 sidecar 검사. 빈 문자열 / `/` 만이면
    /// false (mount root 자체는 절대 sidecar 가 될 수 없음).
    static func isSidecarPath(_ path: String) -> Bool {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !trimmed.isEmpty else { return false }
        guard let lastSlash = trimmed.lastIndex(of: "/") else {
            return isSidecarName(trimmed)
        }
        let leaf = trimmed[trimmed.index(after: lastSlash)...]
        return isSidecarName(String(leaf))
    }
}
