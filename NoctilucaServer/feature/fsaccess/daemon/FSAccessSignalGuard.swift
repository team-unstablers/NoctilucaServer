//
//  FSAccessSignalGuard.swift
//  NoctilucaServer
//
//  SIGTERM / SIGINT 수신 시 NFS 마운트 포인트를 forced unmount 한 뒤
//  ``NSApp.terminate(_:)`` 으로 정상 종료 경로에 진입시키는 supervisor.
//
//  마운트 포인트 path 는 ``NocFSAccessHost`` 가 mount/unmount 시 setter 로
//  갱신한다. 시그널 핸들러 컨텍스트에서 actor 를 건드리지 않도록 lock 으로
//  보호된 글로벌에 path 만 박아두는 형태.
//

import AppKit
import Darwin
import Foundation
import os

import SiriusKit

enum FSAccessSignalGuard {
    private static let logger = NoctilucaLogger(category: "FSAccessSignalGuard")

    /// 현재 활성 NFS 마운트 포인트 path. nil 이면 unmount 할 게 없음.
    private static let activeMountPath = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// DispatchSource retain 용 storage. install() 1회만 호출 가정.
    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []

    static func setActiveMountPath(_ path: String?) {
        activeMountPath.withLock { $0 = path }
    }

    /// 한 번만 호출. AppDelegate.main() 에서 NSApplicationMain 호출 전에.
    static func install() {
        guard sources.isEmpty else { return }

        for signo in [SIGTERM, SIGINT] {
            // DispatchSource 가 시그널을 가로채려면 default disposition 을 꺼야 한다.
            signal(signo, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signo, queue: .main)
            source.setEventHandler {
                handle(signo: signo)
            }
            source.resume()
            sources.append(source)
        }
    }

    private static func handle(signo: Int32) {
        let signalName = (signo == SIGTERM) ? "SIGTERM" : "SIGINT"
        logger.warning("\(signalName) received — unmounting fsaccess mount point and terminating")

        if let path = activeMountPath.withLock({ $0 }) {
            // BSD unmount(2) 직접 호출. mount_nfs / unmount CLI 보다 빠르다.
            // 이미 unmount 된 경우엔 EINVAL 등으로 실패하지만 무시.
            let rc = path.withCString { Darwin.unmount($0, Int32(MNT_FORCE)) }
            if rc != 0 {
                let savedErrno = errno
                logger.warning("forced unmount failed at \(path): errno=\(savedErrno) (\(String(cString: strerror(savedErrno))))")
            } else {
                logger.info("forced unmount succeeded at \(path)")
            }
            activeMountPath.withLock { $0 = nil }
        }

        // 정상 종료 경로 — applicationShouldTerminate → server.shutdown →
        // Sentry / log flush 까지 정상 처리. 시스템 SIGKILL timeout 안에 못
        // 끝내더라도 마운트는 이미 풀려있다.
        NSApp.terminate(nil)
    }
}
