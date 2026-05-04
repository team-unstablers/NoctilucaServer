//
//  NetFSMountController.swift
//  NoctilucaServer
//
//  ``~/NoctilucaFS`` 의 NetFS 마운트 / 언마운트. NetFS.framework 의
//  ``NetFSMountURLAsync`` 는 C 콜백 기반이라 Swift 측에서 wrapping 하기 까다로워,
//  본 stage 의 구현은 *호출 의도* 만 기록하고 실제 마운트는 ``mount_nfs``
//  CLI 호출로 대체하는 stub 으로 시작한다. 추후 NetFS.framework 직접 호출로
//  대체할 예정.
//

import Foundation

import SiriusKit

enum NetFSMountControllerError: Error, CustomStringConvertible {
    case mountFailed(exitCode: Int32, output: String)
    case unmountFailed(exitCode: Int32, output: String)

    var description: String {
        switch self {
        case .mountFailed(let code, let out):
            return "mount_nfs exited \(code): \(out)"
        case .unmountFailed(let code, let out):
            return "umount exited \(code): \(out)"
        }
    }
}

enum NetFSMountController {
    private static let logger = NoctilucaLogger(category: "NetFSMountController")

    /// `nfs://localhost:<port>/` 를 `mountPoint` 에 마운트한다.
    /// 옵션은 docs/nocfsaccessd.md §6.2 의 권장값:
    /// `vers=4,resvport=0,soft,intr,nolocks`.
    static func mount(port: UInt16, mountPoint: URL) async throws {
        let url = "nfs://localhost:\(port)/"
        logger.info("mount: url=\(url) at=\(mountPoint.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount_nfs")
        process.arguments = [
            "-o", "vers=4,resvport=0,soft,intr,nolocks",
            url, mountPoint.path
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

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

    /// `mountPoint` 의 NFS 마운트를 해제한다 (force).
    static func unmount(mountPoint: URL) async throws {
        logger.info("unmount: at=\(mountPoint.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/umount")
        process.arguments = ["-f", mountPoint.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let combined = String(data: err, encoding: .utf8) ?? "<non-utf8>"
            throw NetFSMountControllerError.unmountFailed(
                exitCode: process.terminationStatus, output: combined
            )
        }
    }
}
