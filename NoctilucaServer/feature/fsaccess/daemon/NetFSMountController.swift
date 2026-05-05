//
//  NetFSMountController.swift
//  NoctilucaServer
//
//  ``~/NoctilucaFS`` 의 NFS 마운트 / 언마운트.
//
//  NetFS.framework 의 ``NetFSMountURLAsync`` 는 NFS-specific 옵션 (vers / port /
//  mountport / tcp 등) 을 mount_options dict 로 받지 않아 nanonfs (NFSv4-only,
//  비표준 OS-할당 port) 와 호환되지 않는다. 따라서 ``mount_nfs(8)`` CLI 를 직접
//  호출한다. unmount 는 BSD ``unmount(2, MNT_FORCE)``.
//

import Foundation
import Darwin

import SiriusKit

enum NetFSMountControllerError: Error, CustomStringConvertible {
    case mountFailed(exitCode: Int32, output: String)
    case unmountFailed(errno: Int32)

    var description: String {
        switch self {
        case .mountFailed(let code, let output):
            return "mount_nfs exited \(code): \(output)"
        case .unmountFailed(let e):
            return "unmount(2) failed: errno=\(e) (\(String(cString: strerror(e))))"
        }
    }
}

enum NetFSMountController {
    private static let logger = NoctilucaLogger(category: "NetFSMountController")

    /// `nfs://127.0.0.1:<port>/` 를 `mountPoint` 에 마운트한다.
    /// 옵션: ``vers=4,port=N,mountport=N,tcp,nofail,soft,intr,nolocks``.
    /// nanonfs 가 NFSv4-only 이고 OS-할당 비표준 port 라 vers/port/mountport/tcp
    /// 명시가 필수.
    static func mount(port: UInt16, mountPoint: URL) async throws {
        let url = "noctiluca-fsaccess.localhost:/"
        let options = "vers=4,port=\(port),mountport=\(port),tcp,rsize=1048576,wsize=1048576,dsize=1048576"
        logger.info("mount: url=\(url) at=\(mountPoint.path) options=\(options)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount_nfs")
        process.arguments = ["-o", options, url, mountPoint.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let combined = String(data: err + out, encoding: .utf8) ?? "<non-utf8>"
            throw NetFSMountControllerError.mountFailed(
                exitCode: process.terminationStatus, output: combined
            )
        }
    }

    /// `mountPoint` 의 NFS 마운트를 BSD ``unmount(2, MNT_FORCE)`` 로 강제 해제.
    static func unmount(mountPoint: URL) async throws {
        logger.info("unmount: at=\(mountPoint.path)")
        let result = mountPoint.path.withCString { path in
            Darwin.unmount(path, Int32(MNT_FORCE))
        }
        if result != 0 {
            throw NetFSMountControllerError.unmountFailed(errno: errno)
        }
    }
}
