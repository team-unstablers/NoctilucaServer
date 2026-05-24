//
//  MountPointSupervisor.swift
//  NoctilucaServer
//
//  ``~/NoctilucaFS`` 마운트 포인트 startup 준비. 이전엔 4가지 시나리오를 분기해서
//  검증하던 probe 가 있었지만, SIGKILL 직후 stale NFS mount 위에서 lstat /
//  unmount(2) 가 hang/실패하면 fsaccess 가 영구적으로 비활성화되는 deadlock 이
//  있어 best-effort 패턴으로 단순화했다:
//
//      umount(MNT_FORCE)   // 실패해도 무시
//      mkdir(0o755)        // EEXIST 무시
//      mount_nfs           // 호출자 책임
//
//  사용자가 mountPointPath 로 데이터가 들어있는 디렉토리를 실수로 지정하는 경우의
//  보호장치는 ``mount_nfs`` 가 거기 마운트를 거부할지 여부에 의존한다 — 마운트포인트
//  설정의 책임은 사용자에게 있다.
//

import Foundation

import SiriusKit

enum MountPointSupervisorError: Error, CustomStringConvertible {
    case mkdirFailed(path: String, errno: Int32)

    var description: String {
        switch self {
        case .mkdirFailed(let p, let e):
            return "mkdir failed at \(p): errno=\(e) (\(String(cString: strerror(e))))"
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

    /// `mountPoint` 위에 남아있을 수 있는 stale 마운트를 best-effort 로 정리하고,
    /// 디렉토리가 없으면 생성한다. mkdir 자체가 실패하는 경우만 throw.
    static func prepare(mountPoint: URL) throws {
        let path = mountPoint.path

        // best-effort force unmount. EINVAL = "not currently a mount point" 정상 케이스.
        // 그 외 errno 도 hang/permission 등 가능하지만 모두 무시하고 mount 단계로 진행.
        let unmountRC = unmount(path, Int32(MNT_FORCE))
        if unmountRC == 0 {
            logger.info("prepare: cleaned up stale mount at \(path)")
        } else {
            let savedErrno = errno
            if savedErrno != EINVAL {
                logger.warning("prepare: best-effort unmount failed at \(path): errno=\(savedErrno) (\(String(cString: strerror(savedErrno)))) — proceeding regardless")
            }
        }

        if mkdir(path, 0o755) != 0 {
            let savedErrno = errno
            if savedErrno != EEXIST {
                throw MountPointSupervisorError.mkdirFailed(path: path, errno: savedErrno)
            }
        }
    }
}
