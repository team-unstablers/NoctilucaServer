//
//  FSAccessHandle.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import Foundation
import Darwin

import SiriusKitClient

/// `fsaccess_mount` 채널 위에서 살아 있는 핸들을 표현합니다.
///
/// POSIX file descriptor 또는 directory stream 둘 중 하나를 보관합니다.
/// `closed` 후에는 어떤 연산도 수행하지 않으며, 핸들 ID 는 재사용되지 않습니다.
final class FSAccessHandle: @unchecked Sendable {
    enum Kind {
        case file(fileDescriptor: Int32)
        case directory(dirStream: UnsafeMutablePointer<DIR>)
    }

    let id: UInt64
    let path: URL
    let accessMode: AccessMode
    let openFlags: OpenFlags

    private let lock = NSLock()
    private var _kind: Kind?

    init(id: UInt64, path: URL, accessMode: AccessMode, openFlags: OpenFlags, kind: Kind) {
        self.id = id
        self.path = path
        self.accessMode = accessMode
        self.openFlags = openFlags
        self._kind = kind
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _kind == nil
    }

    var kind: Kind? {
        lock.lock()
        defer { lock.unlock() }
        return _kind
    }

    var fileDescriptor: Int32? {
        guard case .file(let fd) = kind else { return nil }
        return fd
    }

    var dirStream: UnsafeMutablePointer<DIR>? {
        guard case .directory(let dir) = kind else { return nil }
        return dir
    }

    /// 핸들을 닫고 underlying resource 를 해제합니다.
    /// 이미 닫혀 있다면 no-op.
    /// - Returns: 실제로 close 가 호출되었으면 true.
    @discardableResult
    func closeIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let kind = _kind else { return false }
        _kind = nil

        switch kind {
        case .file(let fd):
            _ = Darwin.close(fd)
        case .directory(let dir):
            _ = Darwin.closedir(dir)
        }
        return true
    }

    deinit {
        closeIfNeeded()
    }
}
