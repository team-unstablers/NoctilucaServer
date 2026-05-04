//
//  NocFSAccessDaemonImpl.swift
//  nocfsaccessd
//
//  ``NocFSAccessDaemonProtocol`` 의 NSObject 구현체. 호스트 앱이 본 객체에
//  ``daemonReady`` / ``addConnection`` / ``addMountSession`` 등을 호출한다.
//

import Foundation
import OSLog
import Logging
import NIOCore

import NanoNFS
import NocFSAccessXPC

@objc final class NocFSAccessDaemonImpl: NSObject, NocFSAccessDaemonProtocol, @unchecked Sendable {

    private let virtualTree: VirtualTree
    private let handleTable: HandleTable
    private let server: NoctilucaNFSServer
    private let nanonfsLogger: Logging.Logger

    private nonisolated(unsafe) var listener: NFSServerListener?
    private nonisolated(unsafe) var listenerTask: Task<Void, Error>?

    init(virtualTree: VirtualTree, handleTable: HandleTable) {
        self.virtualTree = virtualTree
        self.handleTable = handleTable
        self.server = NoctilucaNFSServer(virtualTree: virtualTree, handleTable: handleTable)
        var logger = Logging.Logger(label: "pl.unstabler.noctiluca.fsaccessd.nanonfs")
        logger.logLevel = .info
        self.nanonfsLogger = logger
        super.init()
    }

    // MARK: - host → daemon

    func daemonReady(reply: @escaping (UInt16, Error?) -> Void) {
        if listener != nil {
            DaemonLogger.lifecycle.warning("daemonReady invoked twice — replying EALREADY")
            reply(0, NSError.nocFSPosix(EALREADY))
            return
        }
        let listener = NFSServerListener(
            server: server,
            bind: .loopback(port: 0),
            logger: nanonfsLogger
        )
        self.listener = listener

        listenerTask = Task {
            do {
                try await listener.run()
                DaemonLogger.nfs.info("NFSServerListener.run() returned cleanly")
            } catch {
                DaemonLogger.nfs.error("NFSServerListener.run() failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        // boundAddress 폴링 (50ms × 50 = 2.5s).
        Task {
            for _ in 0..<50 {
                if let address = await listener.boundAddress, let port = address.port {
                    DaemonLogger.lifecycle.info("daemonReady: NFSv4 listener bound to localhost:\(port)")
                    reply(UInt16(port), nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            DaemonLogger.lifecycle.error("daemonReady: NFSv4 listener did not bind in time")
            reply(0, NSError.nocFSPosix(EBUSY, message: "NFS listener did not bind in time"))
        }
    }

    func addConnection(connectionLabel: String,
                       displayName: String,
                       reply: @escaping (Error?) -> Void) {
        Task { [virtualTree] in
            await virtualTree.addConnection(label: connectionLabel, displayName: displayName)
            DaemonLogger.vtree.info("addConnection: \(connectionLabel, privacy: .public) (display=\(displayName, privacy: .public))")
            reply(nil)
        }
    }

    func removeConnection(connectionLabel: String,
                          reply: @escaping (Error?) -> Void) {
        Task { [virtualTree, handleTable] in
            let removedSessionIds = await virtualTree.removeConnection(label: connectionLabel)
            for id in removedSessionIds {
                _ = await handleTable.invalidateAll(mountSession: id)
            }
            _ = await handleTable.invalidateAll(connection: connectionLabel)
            DaemonLogger.vtree.info("removeConnection: \(connectionLabel, privacy: .public)")
            reply(nil)
        }
    }

    func addMountSession(descriptor: NocFSMountSessionDescriptor,
                         reply: @escaping (Error?) -> Void) {
        Task { [virtualTree] in
            let ok = await virtualTree.addMountSession(descriptor)
            if ok {
                DaemonLogger.vtree.info("addMountSession: \(descriptor.mountSessionId, privacy: .public) (display=\(descriptor.displayName, privacy: .public))")
                reply(nil)
            } else {
                reply(NSError.nocFSPosix(ENOENT, message: "connectionLabel not found or invalid mountSessionId"))
            }
        }
    }

    func removeMountSession(mountSessionId: String,
                            reply: @escaping (Error?) -> Void) {
        guard let id = UUID(uuidString: mountSessionId) else {
            reply(NSError.nocFSPosix(EINVAL, message: "mountSessionId not a UUID"))
            return
        }
        Task { [virtualTree, handleTable] in
            _ = await virtualTree.removeMountSession(id)
            _ = await handleTable.invalidateAll(mountSession: id)
            DaemonLogger.vtree.info("removeMountSession: \(id.uuidString, privacy: .public)")
            reply(nil)
        }
    }

    func shutdownGracefully(reply: @escaping () -> Void) {
        DaemonLogger.lifecycle.info("shutdownGracefully invoked — stopping NFS listener and exiting")
        listenerTask?.cancel()
        // 호스트가 reply 를 받기 전에 process 가 죽으면 안 되므로 약간의 grace.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            reply()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                exit(0)
            }
        }
    }
}
