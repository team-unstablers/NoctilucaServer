//
//  NocFSAccessDaemonHost.swift
//  NoctilucaServer
//
//  ``nocfsaccessd`` 데몬의 호스트 측 supervisor. ``NSXPCListener.anonymous`` 로
//  엔드포인트를 만들고, 데몬을 자식 프로세스로 띄운 뒤, 데몬이 reverse-connect
//  해 오는 NSXPCConnection 을 받아 호스트 prototype (``NocFSAccessHostProtocol``)
//  과 연결한다.
//
//  데몬 → 호스트 callback 의 실제 dispatch (Sirius msgdef 변환) 는
//  ``NocFSAccessHostXPCExport`` 의 Stage F 구현에서 일어난다. 본 supervisor 는
//  spawn / shutdown / endpoint 전달 / lifecycle 관리만 책임진다.
//

import Foundation

import SiriusKit

import NocFSAccessXPC

// MARK: - Errors

enum NocFSAccessDaemonHostError: Error, CustomStringConvertible {
    case daemonBinaryNotFound(path: String)
    case daemonSpawnFailed(underlying: String)
    case daemonExitedBeforeReady(exitCode: Int32, stderr: String)
    case daemonReadyTimeout

    var description: String {
        switch self {
        case .daemonBinaryNotFound(let path):
            return "nocfsaccessd binary not found at: \(path)"
        case .daemonSpawnFailed(let underlying):
            return "failed to spawn nocfsaccessd: \(underlying)"
        case .daemonExitedBeforeReady(let exit, let err):
            return "nocfsaccessd exited (\(exit)) before reporting ready. stderr=\(err)"
        case .daemonReadyTimeout:
            return "nocfsaccessd did not call daemonReady within the timeout window."
        }
    }
}

// MARK: - Listener delegate

/// NSXPCConnection 은 NSObject + nonSendable. Sending parameter 위배를 피하기
/// 위해 unchecked Sendable wrapper 를 통해 actor 경계를 건너뛴다.
private struct XPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection
}

/// `NSXPCListener` 의 delegate 는 NSObject 여야 한다. 본 객체는 데몬이 host
/// 엔드포인트로 reverse-connect 해 올 때 단 한 번 ``shouldAcceptNewConnection``
/// 가 호출된다 (anonymous endpoint 1:1).
private final class FSAccessListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let hostExport: NocFSAccessHostXPCExport
    private let onAccept: @Sendable (XPCConnectionBox) -> Void

    init(hostExport: NocFSAccessHostXPCExport, onAccept: @escaping @Sendable (XPCConnectionBox) -> Void) {
        self.hostExport = hostExport
        self.onAccept = onAccept
        super.init()
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NocFSAccessXPCInterfaces.makeHostInterface()
        connection.exportedObject = hostExport
        connection.remoteObjectInterface = NocFSAccessXPCInterfaces.makeDaemonInterface()

        // 본 closure 는 nil 로 두고, actor 측에서 onListenerAccepted 가 별도로
        // invalidationHandler / interruptionHandler 를 설치한다.
        connection.resume()
        onAccept(XPCConnectionBox(connection: connection))
        return true
    }
}

// MARK: - NocFSAccessDaemonHost

actor NocFSAccessDaemonHost {
    private let logger = NoctilucaLogger(category: "NocFSAccessDaemonHost")

    static let shared = NocFSAccessDaemonHost()

    /// XPC 환경변수 키. 데몬이 시작 시 본 값을 디코드해 reverse-connect.
    static let endpointEnvKey = "NOC_FSACCESSD_XPC_ENDPOINT"

    private let listener: NSXPCListener = NSXPCListener.anonymous()
    private let hostExport: NocFSAccessHostXPCExport = NocFSAccessHostXPCExport()
    private var listenerDelegate: FSAccessListenerDelegate?

    /// 데몬과의 활성 연결. nil 이면 spawn 전 또는 종료 후.
    private var connection: NSXPCConnection?

    /// 자식 프로세스. nil 이면 spawn 전.
    private var process: Process?

    /// 데몬이 reply 한 NFS bound port. nil 이면 daemonReady 미수신.
    private(set) var nfsPort: UInt16?

    /// `daemonReady` 응답을 기다리는 continuation.
    private var readyContinuation: CheckedContinuation<UInt16, Error>?

    init() {}

    // MARK: - Public lifecycle

    /// 데몬을 띄우고 NFS listener 가 OS 할당 port 를 알릴 때까지 대기한다.
    /// 이미 spawn 된 상태면 기존 port 를 즉시 반환한다.
    @discardableResult
    func startup(timeoutSeconds: Double = 5.0) async throws -> UInt16 {
        if let port = nfsPort {
            return port
        }

        // 이미 listener 가 켜져 있다는 가정 (init 후 자동). delegate 만 설치.
        installListenerDelegateIfNeeded()
        try await spawnDaemonIfNeeded()

        // daemonReady 대기.
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            self.readyContinuation = cont
            // timeout watchdog.
            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                await self.timeoutReadyIfNeeded()
            }

            // 데몬에게 NFS server 시작 요청.
            Task {
                await self.kickoffDaemonReady()
            }
        }
    }

    /// graceful shutdown → SIGTERM → SIGKILL 시퀀스.
    func shutdown(gracePeriodSeconds: Double = 5.0) async {
        guard let process else { return }

        logger.info("shutdown: requesting graceful daemon exit (pid=\(process.processIdentifier))")

        if let proxy = remoteDaemonProxy() {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                proxy.shutdownGracefully {
                    cont.resume()
                }
            }
        }

        // grace period 대기.
        let deadlineMs = Int(gracePeriodSeconds * 1000)
        let pollIntervalMs = 100
        var elapsedMs = 0
        while process.isRunning && elapsedMs < deadlineMs {
            try? await Task.sleep(for: .milliseconds(pollIntervalMs))
            elapsedMs += pollIntervalMs
        }

        if process.isRunning {
            logger.warning("shutdown: daemon ignored shutdownGracefully — sending SIGTERM")
            process.terminate()
            elapsedMs = 0
            while process.isRunning && elapsedMs < deadlineMs {
                try? await Task.sleep(for: .milliseconds(pollIntervalMs))
                elapsedMs += pollIntervalMs
            }
        }

        if process.isRunning {
            logger.warning("shutdown: daemon ignored SIGTERM — escalating to SIGKILL")
            kill(process.processIdentifier, SIGKILL)
        }

        connection?.invalidate()
        connection = nil
        self.process = nil
        nfsPort = nil
    }

    // MARK: - host → daemon proxies (Stage E-G 가 호출)

    /// 1단계 connection namespace 추가.
    func addConnection(connectionLabel: String, displayName: String) async throws {
        guard let proxy = remoteDaemonProxy() else { throw NocFSAccessDaemonHostError.daemonReadyTimeout }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.addConnection(connectionLabel: connectionLabel, displayName: displayName) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func removeConnection(connectionLabel: String) async throws {
        guard let proxy = remoteDaemonProxy() else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.removeConnection(connectionLabel: connectionLabel) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func addMountSession(_ descriptor: NocFSMountSessionDescriptor) async throws {
        guard let proxy = remoteDaemonProxy() else { throw NocFSAccessDaemonHostError.daemonReadyTimeout }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.addMountSession(descriptor: descriptor) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func removeMountSession(_ id: UUID) async throws {
        guard let proxy = remoteDaemonProxy() else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.removeMountSession(mountSessionId: id.uuidString) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    // MARK: - Internals

    private func installListenerDelegateIfNeeded() {
        guard listenerDelegate == nil else { return }
        let host = hostExport
        let delegate = FSAccessListenerDelegate(hostExport: host) { [weak self] box in
            // delegate 가 connection accept 시 호출. nonisolated 에서 actor 로 hop.
            self?.dispatchListenerAccepted(box)
        }
        listener.delegate = delegate
        listener.resume()
        listenerDelegate = delegate
    }

    nonisolated private func dispatchListenerAccepted(_ box: XPCConnectionBox) {
        Task { [weak self] in
            await self?.onListenerAccepted(box)
        }
    }

    nonisolated private func dispatchConnectionLost(reason: String) {
        Task { [weak self] in
            await self?.onConnectionLost(reason: reason)
        }
    }

    nonisolated private func dispatchProxyError(_ error: Error) {
        Task { [weak self] in
            await self?.handleProxyError(error)
        }
    }

    private func onListenerAccepted(_ box: XPCConnectionBox) {
        logger.info("daemon connected; storing NSXPCConnection")
        let newConnection = box.connection
        self.connection = newConnection

        // invalidation / interruption 시 cleanup. nonisolated 메서드를 거쳐 actor hop.
        newConnection.invalidationHandler = { [weak self] in
            self?.dispatchConnectionLost(reason: "invalidated")
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.dispatchConnectionLost(reason: "interrupted")
        }
    }

    private func onConnectionLost(reason: String) {
        logger.warning("XPC connection lost (\(reason)) — daemon assumed dead")
        connection = nil
        nfsPort = nil
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: NocFSAccessDaemonHostError.daemonReadyTimeout)
        }
    }

    private func remoteDaemonProxy() -> (any NocFSAccessDaemonProtocol)? {
        let proxy = connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.dispatchProxyError(error)
        }
        return proxy as? NocFSAccessDaemonProtocol
    }

    private func handleProxyError(_ error: Error) {
        logger.error("XPC proxy error: \(error)")
    }

    private func kickoffDaemonReady() async {
        // 데몬에게 NFS server 시작 요청. reply 받으면 readyContinuation 을 resume.
        guard let proxy = remoteDaemonProxy() else {
            // 아직 connection 없음. spawnDaemon 직후 곧 도착할 거. polling 으로 대기.
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(100))
                if remoteDaemonProxy() != nil { break }
            }
            guard let proxy = remoteDaemonProxy() else { return }
            await invokeDaemonReady(proxy)
            return
        }
        await invokeDaemonReady(proxy)
    }

    private func invokeDaemonReady(_ proxy: any NocFSAccessDaemonProtocol) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            proxy.daemonReady { [weak self] port, error in
                Task { [weak self] in
                    await self?.handleDaemonReady(port: port, error: error)
                    cont.resume()
                }
            }
        }
    }

    private func handleDaemonReady(port: UInt16, error: Error?) {
        if let error {
            logger.error("daemonReady failed: \(error)")
            if let cont = readyContinuation {
                readyContinuation = nil
                cont.resume(throwing: error)
            }
            return
        }
        nfsPort = port
        logger.info("daemonReady: nfsPort=\(port)")
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(returning: port)
        }
    }

    private func timeoutReadyIfNeeded() {
        guard readyContinuation != nil else { return }
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: NocFSAccessDaemonHostError.daemonReadyTimeout)
        }
    }

    private func spawnDaemonIfNeeded() async throws {
        if process != nil { return }

        let helperURL = try Self.resolveHelperURL()
        let endpointBase64 = try encodeEndpoint(listener.endpoint)

        let proc = Process()
        proc.executableURL = helperURL

        // 호스트 사망 시 자식의 stdin 이 EOF 가 되도록 lifetime pipe 를 묶는다.
        let lifetimePipe = Pipe()
        proc.standardInput = lifetimePipe

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        // 환경변수: 최소화 + endpoint.
        var env = ProcessInfo.processInfo.environment
        env[Self.endpointEnvKey] = endpointBase64
        proc.environment = env

        proc.terminationHandler = { [weak self] terminated in
            Task { await self?.handleProcessExit(terminated.terminationStatus) }
        }

        do {
            try proc.run()
        } catch {
            throw NocFSAccessDaemonHostError.daemonSpawnFailed(underlying: "\(error)")
        }

        process = proc
        logger.info("daemon spawned: pid=\(proc.processIdentifier) helper=\(helperURL.path)")

        // stderr 를 백그라운드에서 logger 로 흘려보낸다.
        Self.startStderrLogPump(handle: stderrPipe.fileHandleForReading, logger: logger)

        // lifetime pipe 의 write end 는 process 가 살아있는 동안 open 유지.
        // 호스트가 죽으면 pipe 가 닫히고 자식 stdin EOF 가 됨 → 데몬은
        // invalidationHandler 로 자체 종료.
        _ = lifetimePipe
    }

    private func handleProcessExit(_ status: Int32) {
        logger.info("daemon exited: status=\(status)")
        process = nil
        connection?.invalidate()
        connection = nil
        nfsPort = nil
    }

    // MARK: - Helpers

    private func encodeEndpoint(_ endpoint: NSXPCListenerEndpoint) throws -> String {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(endpoint, forKey: "endpoint")
        return archiver.encodedData.base64EncodedString()
    }

    private static func resolveHelperURL() throws -> URL {
        guard let mainExecutable = Bundle.main.executableURL else {
            throw NocFSAccessDaemonHostError.daemonBinaryNotFound(path: "<Bundle.main.executableURL is nil>")
        }
        let helperURL = mainExecutable
            .deletingLastPathComponent()
            .appendingPathComponent("nocfsaccessd")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw NocFSAccessDaemonHostError.daemonBinaryNotFound(path: helperURL.path)
        }
        return helperURL
    }

    private static func startStderrLogPump(handle: FileHandle, logger: SiriusLogger) {
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .newlines)
                    if !trimmed.isEmpty {
                        logger.info("[nocfsaccessd] \(trimmed)")
                    }
                }
            }
        }
    }
}
