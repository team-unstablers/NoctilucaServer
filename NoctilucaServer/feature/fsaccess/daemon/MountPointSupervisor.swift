//
//  MountPointSupervisor.swift
//  NoctilucaServer
//
//  ``~/NoctilucaFS`` 마운트 포인트의 startup probe 와 cleanup. docs/nocfsaccessd.md
//  §6.3 의 4가지 시나리오:
//
//  1. 존재하지 않음 → mkdir(0o755) 로 생성.
//  2. 존재 + 일반 빈 디렉토리 → 그대로 재사용.
//  3. 존재 + 마운트 포인트 → 이전 실행의 stale 마운트로 간주 → forced umount → 빈 디렉토리.
//  4. 존재 + 일반 디렉토리지만 비어있지 않음 → fsaccess feature 비활성 + 사용자 알림.
//

import Foundation

import SiriusKit

enum MountPointSupervisorResult: Sendable {
    /// 즉시 마운트 가능한 빈 디렉토리.
    case ready(mountPoint: URL)
    /// 비어있지 않은 일반 디렉토리. fsaccess 를 비활성화해야 함.
    case nonEmpty(mountPoint: URL, entries: [String])
}

enum MountPointSupervisorError: Error, CustomStringConvertible {
    case mkdirFailed(path: String, errno: Int32)
    case statFailed(path: String, errno: Int32)
    case forcedUnmountFailed(path: String, errno: Int32)
    case readDirectoryFailed(path: String, underlying: any Error)

    var description: String {
        switch self {
        case .mkdirFailed(let p, let e):
            return "mkdir failed at \(p): errno=\(e) (\(String(cString: strerror(e))))"
        case .statFailed(let p, let e):
            return "stat failed at \(p): errno=\(e) (\(String(cString: strerror(e))))"
        case .forcedUnmountFailed(let p, let e):
            return "forced unmount failed at \(p): errno=\(e) (\(String(cString: strerror(e))))"
        case .readDirectoryFailed(let p, let err):
            return "readDirectory failed at \(p): \(err)"
        }
    }
}

enum MountPointSupervisor {
    private static let logger = NoctilucaLogger(category: "MountPointSupervisor")

    /// `path` 를 `~/` 또는 `$HOME/...` 형태로 받아 사용자 home 기준으로 풀어낸다.
    static func resolveMountPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// 마운트 포인트를 점검하고 결과를 리턴한다.
    /// 호출자는 ``.ready`` 일 때만 NetFS 마운트를 시도하고, ``.nonEmpty`` 일 때는
    /// fsaccess feature 를 비활성화한다.
    static func probe(mountPoint: URL) throws -> MountPointSupervisorResult {
        let path = mountPoint.path
        var statBuffer = stat()
        let statResult = lstat(path, &statBuffer)

        if statResult != 0 {
            let savedErrno = errno
            if savedErrno == ENOENT {
                logger.info("mount point does not exist; creating: \(path)")
                if mkdir(path, 0o755) != 0 {
                    throw MountPointSupervisorError.mkdirFailed(path: path, errno: errno)
                }
                return .ready(mountPoint: mountPoint)
            }
            throw MountPointSupervisorError.statFailed(path: path, errno: savedErrno)
        }

        // st_mode S_IFDIR 검사 — symlink 등은 거절.
        let isDirectory = (statBuffer.st_mode & S_IFMT) == S_IFDIR
        guard isDirectory else {
            // 디렉토리가 아니면 사용자에게 알리고 거절. 일단 nonEmpty 로 환원.
            return .nonEmpty(mountPoint: mountPoint, entries: ["<not-a-directory>"])
        }

        // 마운트 포인트 여부 — 부모와 device id (st_dev) 가 다르면 마운트된 것.
        let parentPath = mountPoint.deletingLastPathComponent().path
        var parentStat = stat()
        let parentRC = lstat(parentPath, &parentStat)
        let isMountPoint: Bool
        if parentRC == 0 {
            isMountPoint = parentStat.st_dev != statBuffer.st_dev
        } else {
            isMountPoint = false
        }

        if isMountPoint {
            logger.warning("mount point \(path) appears to host a stale mount — issuing forced unmount")
            // unmount(2) 의 두 번째 인자 = MNT_FORCE.
            if unmount(path, Int32(MNT_FORCE)) != 0 {
                let savedErrno = errno
                logger.error("forced unmount failed: errno=\(savedErrno) — proceeding regardless (we'll re-stat)")
                throw MountPointSupervisorError.forcedUnmountFailed(path: path, errno: savedErrno)
            }
            return .ready(mountPoint: mountPoint)
        }

        // 일반 디렉토리. 비어있는지 검사.
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            throw MountPointSupervisorError.readDirectoryFailed(path: path, underlying: error)
        }

        // .DS_Store 만 있는 경우는 비어있음으로 간주 (관용 — Finder 가 자주 만든다).
        let nontrivial = entries.filter { $0 != ".DS_Store" }
        if nontrivial.isEmpty {
            return .ready(mountPoint: mountPoint)
        }
        return .nonEmpty(mountPoint: mountPoint, entries: entries)
    }
}
