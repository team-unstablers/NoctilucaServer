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

    /// `AppSettings.FileAccess.useFakeLocks` 의 캐시. `true` 면 NFS LOCK / LOCKT
    /// / LOCKU callback 이 navigator 의 `supportsLocks` 광고를 무시하고 fake
    /// success 로 응답한다. `NoctilucaNFSServer` 가 cross-actor read 로 참조.
    private(set) var useFakeLocks: Bool = false

    /// 1단계 connection namespace 의 monotonic counter (docs §5.1.1).
    private var nextConnectionNumber: Int = 1

    private let nanonfsLogger: Logging.Logger = {
        var l = Logging.Logger(label: "pl.unstabler.noctiluca.fsaccess.nanonfs")
        l.logLevel = .debug
        return l
    }()

    init() {}

    // MARK: - Public lifecycle

    /// fsaccess feature 가 enabled 면 NFS listener 시작 + mount point 준비 +
    /// NetFS 마운트까지 수행. disabled 면 noop.
    func startupIfEnabled(enabled: Bool, mountPointPath: String, useFakeLocks: Bool = false) async {
        self.useFakeLocks = useFakeLocks
        guard enabled else {
            logger.info("startupIfEnabled: fsaccess feature is disabled — skipping NFS listener.")
            return
        }
        let mountPoint = MountPointSupervisor.resolveMountPath(mountPointPath)
        do {
            try MountPointSupervisor.prepare(mountPoint: mountPoint)
            self.mountPointURL = mountPoint
        } catch {
            logger.error("startupIfEnabled: mount point preparation failed: \(error.localizedDescription) — fsaccess disabled.")
            return
        }
        do {
            let port = try await self.startListener()
            try await NetFSMountController.mount(port: port, mountPoint: mountPoint)
            FSAccessSignalGuard.setActiveMountPath(mountPoint.path)
            logger.info("startupIfEnabled: NFS mount established at \(mountPoint.path) (port=\(port)).")
        } catch {
            logger.error("startupIfEnabled: failed: \(error.localizedDescription) — fsaccess disabled for this run.")
            // await self.stopListener()
        }
    }

    /// 사용자가 설정 토글로 `useFakeLocks` 를 변경했을 때 즉시 반영. 이미 활성화된
    /// mount session 의 다음 NFS LOCK / LOCKT / LOCKU 부터 새 정책이 적용된다.
    func setUseFakeLocks(_ value: Bool) {
        if useFakeLocks != value {
            logger.info("setUseFakeLocks: \(self.useFakeLocks) → \(value)")
            useFakeLocks = value
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
            FSAccessSignalGuard.setActiveMountPath(nil)
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
        logger.info("addMountSession: label=\(connectionLabel) sessionId=\(mountSessionId.uuidString) displayName='\(displayName)' grantedAccess=\(grantedAccess)")
        return await virtualTree.addMountSession(
            connectionLabel: connectionLabel,
            mountSessionId: mountSessionId,
            displayName: displayName,
            grantedAccess: grantedAccess
        )
    }

    func removeMountSession(_ id: UUID) async {
        // mount session 의 fsaccess_mount channel 이 아직 살아있으면 (host-
        // initiated 명시 unmount 등) navigator 측에 남아있는 모든 OPEN slot 을
        // best-effort 로 close 해 navigator 측 handle table inflate 를 회수한다.
        // channel 이 이미 죽었으면 (peer-initiated close 후 cleanup) channel 의
        // teardown 흐름이 메모리만 비우고, 여기 sendClose 호출은 throw 되어
        // try? 가 흡수.
        if let channel = await FSAccessRequestRouter.shared.channel(for: id) {
            let slots = await channel.openSlotTable.drainAll()
            if !slots.isEmpty {
                logger.info("removeMountSession: draining \(slots.count) OpenSlot(s) for session=\(id.uuidString)")
            }
            for slot in slots {
                _ = try? await channel.sendClose(handleId: slot.navigatorHandleId)
            }
        }
        _ = await virtualTree.removeMountSession(id)
        _ = await handleTable.invalidateAll(mountSession: id)
    }

    // MARK: - Internal: NFS listener

    private func startListener(timeoutSeconds: Double = 5.0) async throws -> UInt16 {
        if let port = nfsPort { return port }
        let server = NoctilucaNFSServer(virtualTree: virtualTree, handleTable: handleTable)
        // port 0 → OS-할당 ephemeral. 같은 사용자의 다른 프로세스가 hardcoded
        // port 로 직접 connect 해 AUTH_SYS UID 를 spoof 하는 surface 를 좁힌다.
        // 실제 bound port 는 `NFSServerListener.boundAddress` polling 으로
        // 받아 NetFSMountController.mount 에 그대로 넘겨준다.
        let listener = NFSServerListener(
            server: server, bind: .loopback(port: 0), logger: nanonfsLogger
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
            if let address = await listener.boundAddress {
                let port = address.port
                self.nfsPort = port
                logger.info("NFS listener bound: localhost:\(port)")
                return port
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
