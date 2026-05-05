//
//  NocFSAccessHost.swift
//  NoctilucaServer
//
//  fsaccess feature 의 host-app-internal supervisor. 데몬 분리를 포기한 옵션 A
//  디자인에서는 본 actor 가 host app 안에서 직접 ``NFSServerListener`` 를
//  띄우고 가상 트리 / 핸들 테이블을 보유한다 (이전 NocFSAccessDaemonHost 의
//  spawn / XPC 코드는 모두 제거됨).
//

import Foundation
import Logging
import NIOCore

import NanoNFS

import SiriusKit

enum NocFSAccessHostError: Error, CustomStringConvertible {
    case listenerStartTimeout

    var description: String {
        switch self {
        case .listenerStartTimeout: return "NFSServerListener did not bind in the timeout window."
        }
    }
}

actor NocFSAccessHost {
    private let logger = NoctilucaLogger(category: "NocFSAccessHost")

    static let shared = NocFSAccessHost()

    let virtualTree = VirtualTree()
    let handleTable = HandleTable()

    private var listener: NFSServerListener?
    private var listenerTask: Task<Void, Error>?
    /// 현재 NFSv4 listen 중인 OS-할당 port. nil 이면 not started.
    private(set) var nfsPort: UInt16?

    /// 마운트 포인트 URL (`startupIfEnabled` 시 결정).
    private(set) var mountPointURL: URL?

    /// 1단계 connection namespace 의 monotonic counter (docs §5.1.1).
    private var nextConnectionNumber: Int = 1

    private let nanonfsLogger: Logging.Logger = {
        var l = Logging.Logger(label: "pl.unstabler.noctiluca.fsaccess.nanonfs")
        l.logLevel = .debug
        return l
    }()

    init() {}

    // MARK: - Public lifecycle

    /// fsaccess feature 가 enabled 면 NFS listener 시작 + mount point probe +
    /// NetFS 마운트까지 수행. disabled 또는 마운트 포인트가 non-empty 면 noop.
    func startupIfEnabled(enabled: Bool, mountPointPath: String) async {
        guard enabled else {
            logger.info("startupIfEnabled: fsaccess feature is disabled — skipping NFS listener.")
            return
        }
        let mountPoint = MountPointSupervisor.resolveMountPath(mountPointPath)
        do {
            let probe = try MountPointSupervisor.probe(mountPoint: mountPoint)
            switch probe {
            case .ready:
                self.mountPointURL = mountPoint
            case .nonEmpty(let url, let entries):
                logger.warning("startupIfEnabled: mount point \(url.path) is not empty (\(entries.count) entries) — refusing to mount and disabling fsaccess for this run.")
                return
            }
        } catch {
            logger.error("startupIfEnabled: mount point probe failed: \(error.localizedDescription) — fsaccess disabled.")
            return
        }
        do {
            let port = try await self.startListener()
            try await NetFSMountController.mount(port: port, mountPoint: mountPoint)
            logger.info("startupIfEnabled: NFS mount established at \(mountPoint.path) (port=\(port)).")
        } catch {
            logger.error("startupIfEnabled: failed: \(error.localizedDescription) — fsaccess disabled for this run.")
            // await self.stopListener()
        }
    }

    /// startupIfEnabled 의 inverse — unmount 후 listener stop.
    func shutdownAndUnmount() async {
        if let mountPoint = mountPointURL {
            do {
                try await NetFSMountController.unmount(mountPoint: mountPoint)
            } catch {
                logger.warning("shutdownAndUnmount: unmount failed: \(error.localizedDescription)")
            }
        }
        await self.stopListener()
        mountPointURL = nil
    }

    /// `NNNN-username` 형식의 1단계 connection label 을 발급.
    func issueConnectionLabel(username: String) -> String {
        let n = nextConnectionNumber
        nextConnectionNumber &+= 1
        if nextConnectionNumber == 0 { nextConnectionNumber = 1 }
        let formatted = String(format: "%04d", n)
        let safe = username.isEmpty ? "unknown" : username
        return "\(formatted)-\(safe)"
    }

    // MARK: - VirtualTree push (전 host → daemon XPC 였던 것)

    func addConnection(connectionLabel: String, displayName: String) async {
        await virtualTree.addConnection(label: connectionLabel, displayName: displayName)
    }

    func removeConnection(connectionLabel: String) async {
        let removedSessions = await virtualTree.removeConnection(label: connectionLabel)
        for id in removedSessions {
            _ = await handleTable.invalidateAll(mountSession: id)
        }
        _ = await handleTable.invalidateAll(connection: connectionLabel)
    }

    func addMountSession(connectionLabel: String,
                         mountSessionId: UUID,
                         displayName: String,
                         grantedAccess: UInt32) async -> Bool {
        return await virtualTree.addMountSession(
            connectionLabel: connectionLabel,
            mountSessionId: mountSessionId,
            displayName: displayName,
            grantedAccess: grantedAccess
        )
    }

    func removeMountSession(_ id: UUID) async {
        _ = await virtualTree.removeMountSession(id)
        _ = await handleTable.invalidateAll(mountSession: id)
    }

    // MARK: - Internal: NFS listener

    private func startListener(timeoutSeconds: Double = 5.0) async throws -> UInt16 {
        if let port = nfsPort { return port }
        let server = NoctilucaNFSServer(virtualTree: virtualTree, handleTable: handleTable)
        let listener = NFSServerListener(
            server: server, bind: .loopback(port: 25440), logger: nanonfsLogger
        )
        self.listener = listener

        let listenerTask = Task {
            do {
                try await listener.run()
                self.logger.info("NFSServerListener.run() returned cleanly")
            } catch {
                self.logger.error("NFSServerListener.run() failed: \(error.localizedDescription)")
                throw error
            }
        }
        self.listenerTask = listenerTask

        // boundAddress polling (50ms × 100 = 5s).
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let address = await listener.boundAddress, let port = address.port {
                let port16 = UInt16(port)
                self.nfsPort = port16
                logger.info("NFS listener bound: localhost:\(port16)")
                return port16
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        throw NocFSAccessHostError.listenerStartTimeout
    }

    private func stopListener() async {
        listenerTask?.cancel()
        listenerTask = nil
        listener = nil
        nfsPort = nil
    }
}
