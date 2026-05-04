//
//  NetFSMountController.swift
//  NoctilucaServer
//
//  ``~/NoctilucaFS`` 의 NetFS 마운트 / 언마운트. NetFS.framework 의
//  ``NetFSMountURLAsync`` 를 사용해 user-level NFS 마운트를 수행하고, unmount
//  는 BSD ``unmount(2)`` (NetFS 자체에는 unmount 진입점이 없음).
//
//  NetFS API 의 mount_options / open_options 키 의미는 ``NetFS.h`` 헤더 참고.
//

import Foundation
import Darwin

import NetFS

import SiriusKit

enum NetFSMountControllerError: Error, CustomStringConvertible {
    /// `NetFSMountURLAsync` 의 dispatch 자체가 실패 (양수 = errno, 음수 = OSStatus).
    case dispatchFailed(status: Int32)
    /// 콜백에 전달된 mount status 가 비-0 (양수 = errno, 음수 = OSStatus).
    case mountFailed(status: Int32)
    /// `unmount(2)` 가 실패.
    case unmountFailed(errno: Int32)

    var description: String {
        switch self {
        case .dispatchFailed(let s):
            return "NetFSMountURLAsync dispatch failed: status=\(s) (\(Self.statusDescription(s)))"
        case .mountFailed(let s):
            return "NetFSMountURLAsync mount failed: status=\(s) (\(Self.statusDescription(s)))"
        case .unmountFailed(let e):
            return "unmount(2) failed: errno=\(e) (\(String(cString: strerror(e))))"
        }
    }

    private static func statusDescription(_ status: Int32) -> String {
        if status > 0 {
            return "errno: " + String(cString: strerror(status))
        }
        switch status {
        case -128: return "userCanceledErr"
        case ENETFSPWDNEEDSCHANGE: return "ENETFSPWDNEEDSCHANGE"
        case ENETFSPWDPOLICY: return "ENETFSPWDPOLICY"
        case ENETFSACCOUNTRESTRICTED: return "ENETFSACCOUNTRESTRICTED"
        case ENETFSNOSHARESAVAIL: return "ENETFSNOSHARESAVAIL"
        case ENETFSNOAUTHMECHSUPP: return "ENETFSNOAUTHMECHSUPP"
        case ENETFSNOPROTOVERSSUPP: return "ENETFSNOPROTOVERSSUPP"
        default: return "OSStatus"
        }
    }
}

enum NetFSMountController {
    private static let logger = NoctilucaLogger(category: "NetFSMountController")

    /// `nfs://localhost:<port>/` 를 `mountPoint` 에 마운트한다.
    ///
    /// - Note: NetFS API 는 NFSv4 / version / `resvport=0` / `nolocks` 등의
    ///   NFS-specific 옵션을 directly 받지 않는다. 우리는 nanonfs 가 NFSv4
    ///   리스너인 것에 의지해 NetFS 의 자동 버전 협상이 v4 를 고르도록 둔다.
    ///   loopback 은 명시적 opt-in 이 필요하므로 ``kNetFSAllowLoopbackKey`` 를
    ///   true 로 설정한다.
    static func mount(port: UInt16, mountPoint: URL) async throws {
        let url = URL(string: "nfs://localhost:\(port)/")!
        logger.info("mount: url=\(url.absoluteString) at=\(mountPoint.path)")

        let openOptions = NSMutableDictionary()
        openOptions[kNetFSAllowLoopbackKey] = true
        openOptions[kNAUIOptionKey] = kNAUIOptionNoUI

        let mountOptions = NSMutableDictionary()
        // 명시한 mountpath 정확히 그 자리에 마운트 (하위 디렉토리 만들지 않음).
        mountOptions[kNetFSMountAtMountDirKey] = true
        mountOptions[kNetFSSoftMountKey] = true

        let queue = DispatchQueue(label: "pl.unstabler.noctiluca.netfs.mount", qos: .userInitiated)

        let status: Int32 = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            var requestID: AsyncRequestID?
            let dispatchResult = NetFSMountURLAsync(
                url as CFURL,
                mountPoint as CFURL,
                nil, nil,
                openOptions as! CFMutableDictionary,
                mountOptions as! CFMutableDictionary,
                &requestID,
                queue
            ) { mountStatus, _, _ in
                cont.resume(returning: mountStatus)
            }
            if dispatchResult != 0 {
                cont.resume(throwing: NetFSMountControllerError.dispatchFailed(status: dispatchResult))
            }
        }

        if status != 0 {
            throw NetFSMountControllerError.mountFailed(status: status)
        }
        logger.info("mount: NetFSMountURLAsync succeeded at \(mountPoint.path).")
    }

    /// `mountPoint` 의 NFS 마운트를 BSD `unmount(2)` 로 강제 해제한다.
    /// NetFS 자체에는 unmount 진입점이 없다.
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
