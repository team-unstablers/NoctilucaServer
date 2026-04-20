//
//  VirtualDisplayManager.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation
import CoreGraphics

import SiriusKitCore

enum VirtualDisplayManagerError: Error, Sendable, CustomStringConvertible {
    case helperNotFound(path: String)
    case helperSpawnFailed(underlying: String)
    case helperExitedBeforeReady(exitCode: Int32, stderr: String)
    case invalidDisplayIDOutput(raw: String)
    case duplicateIdentifier(NOCVirtualDisplayIdentifier)

    var description: String {
        switch self {
        case .helperNotFound(let path):
            return "nocvirtdisplay helper not found at: \(path)"
        case .helperSpawnFailed(let underlying):
            return "failed to spawn helper: \(underlying)"
        case .helperExitedBeforeReady(let exitCode, let stderr):
            return "helper exited (\(exitCode)) before reporting DisplayID. stderr: \(stderr)"
        case .invalidDisplayIDOutput(let raw):
            return "helper stdout was not a DisplayID: '\(raw)'"
        case .duplicateIdentifier(let id):
            return "duplicate virtual display identifier: \(id)"
        }
    }
}

extension NOCDisplaySpec {
    /// `nocvirtdisplay` CLI 포맷 문자열로 직렬화한다.
    ///
    /// 예) `1920x1080@60+2x`, `2560x1440@?+1x` (refreshRate=0일 때 `?`로 표기)
    func toCLIString() -> String {
        let w = Int(resolution.width)
        let h = Int(resolution.height)
        let r = refreshRate > 0 ? String(format: "%g", refreshRate) : "?"
        let s = scaleFactor > 1 ? "+\(Int(scaleFactor))x" : "+1x"
        return "\(w)x\(h)@\(r)\(s)"
    }
}

/// actor 내부 전용 래퍼. Process + 연결된 Pipe들을 한 묶음으로 관리한다.
/// Process 자체는 Sendable이 아니지만, 접근은 VirtualDisplayManager actor 내부에서만 이뤄진다.
private final class VirtualDisplayProcess: @unchecked Sendable {
    let identifier: NOCVirtualDisplayIdentifier
    let sessionID: UUID
    let purpose: NOCVirtualDisplayPurpose
    let displayID: CGDirectDisplayID
    let process: Process
    /// 부모가 write end를 process 생존 기간 내내 open 상태로 유지.
    /// 부모 사망 시 write end가 자동 close되면서 자식 stdin이 EOF를 받는다.
    let lifetimePipe: Pipe

    init(
        identifier: NOCVirtualDisplayIdentifier,
        sessionID: UUID,
        purpose: NOCVirtualDisplayPurpose,
        displayID: CGDirectDisplayID,
        process: Process,
        lifetimePipe: Pipe
    ) {
        self.identifier = identifier
        self.sessionID = sessionID
        self.purpose = purpose
        self.displayID = displayID
        self.process = process
        self.lifetimePipe = lifetimePipe
    }
}

/// `nocvirtdisplay` 헬퍼 바이너리를 서브프로세스로 띄워 가상 디스플레이의 수명을 관리한다.
///
/// - 하나의 가상 디스플레이 = 하나의 helper 프로세스.
/// - helper 프로세스 종료(SIGTERM/SIGKILL/crash) 시 WindowServer가 XPC 연결 종료를 감지해
///   해당 프로세스가 생성한 VD를 자동으로 제거한다.
/// - 부모(NoctilucaServer) 사망 시에도 lifetime pipe EOF로 helper가 자진 종료하도록 설계됨.
actor VirtualDisplayManager {
    private let logger = NoctilucaLogger(category: "VirtualDisplayManager")

    private var processes: [NOCVirtualDisplayIdentifier: VirtualDisplayProcess] = [:]

    init() {}

    // MARK: - Public API

    func spawn(
        ownedBy sessionID: UUID,
        purpose: NOCVirtualDisplayPurpose,
        specs: [NOCDisplaySpec]
    ) async throws -> NOCVirtualDisplayHandle {
        let shortID = String(UUID().uuidString.prefix(8))
        let identifier: NOCVirtualDisplayIdentifier =
            "app.noctiluca.server.\(sessionID.uuidString).virtual-display.\(shortID)"

        guard processes[identifier] == nil else {
            throw VirtualDisplayManagerError.duplicateIdentifier(identifier)
        }

        let helperURL = try Self.resolveHelperURL()

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--identifier", shortID] + specs.map { $0.toCLIString() }

        let lifetimePipe = Pipe()
        process.standardInput = lifetimePipe
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        logger.info("spawn: launching helper identifier=\(identifier) specs=\(specs.map { $0.toCLIString() })")

        do {
            try process.run()
        } catch {
            throw VirtualDisplayManagerError.helperSpawnFailed(underlying: "\(error)")
        }

        // stdout 첫 줄(= DisplayID)을 읽는다. helper가 먼저 exit하면 empty Data(EOF).
        let firstLine: String?
        do {
            firstLine = try await Self.readFirstLine(from: stdoutPipe.fileHandleForReading)
        } catch {
            firstLine = nil
        }

        guard let line = firstLine else {
            process.waitUntilExit()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrStr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.error("spawn: helper exited before DisplayID; exitCode=\(process.terminationStatus) stderr=\(stderrStr)")
            throw VirtualDisplayManagerError.helperExitedBeforeReady(
                exitCode: process.terminationStatus,
                stderr: stderrStr
            )
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let displayID = CGDirectDisplayID(trimmed), displayID != 0 else {
            logger.error("spawn: invalid DisplayID output '\(trimmed)'; terminating helper")
            process.terminate()
            throw VirtualDisplayManagerError.invalidDisplayIDOutput(raw: trimmed)
        }

        logger.info("spawn: helper ready. identifier=\(identifier) displayID=\(displayID) pid=\(process.processIdentifier)")

        let wrapper = VirtualDisplayProcess(
            identifier: identifier,
            sessionID: sessionID,
            purpose: purpose,
            displayID: displayID,
            process: process,
            lifetimePipe: lifetimePipe
        )
        processes[identifier] = wrapper

        return NOCVirtualDisplayHandle(
            identifier: identifier,
            displayID: displayID,
            purpose: purpose,
            metadata: [:]
        )
    }

    func destroy(_ handle: NOCVirtualDisplayHandle) async {
        guard let wrapper = processes.removeValue(forKey: handle.identifier) else {
            logger.warning("destroy: no process for identifier=\(handle.identifier) (already destroyed?)")
            return
        }
        await terminate(wrapper)
    }

    func destroyAll(ownedBy sessionID: UUID) async {
        let targets = processes.values.filter { $0.sessionID == sessionID }
        guard !targets.isEmpty else { return }

        for wrapper in targets {
            processes.removeValue(forKey: wrapper.identifier)
        }

        await withTaskGroup(of: Void.self) { group in
            for wrapper in targets {
                group.addTask { [self] in
                    await terminate(wrapper)
                }
            }
        }
    }

    func shutdown() async {
        let all = Array(processes.values)
        processes.removeAll()

        guard !all.isEmpty else { return }

        logger.info("shutdown: terminating \(all.count) helper process(es)")
        await withTaskGroup(of: Void.self) { group in
            for wrapper in all {
                group.addTask { [self] in
                    await terminate(wrapper)
                }
            }
        }
    }

    // MARK: - Internals

    /// 해당 helper에 SIGTERM을 보낸 뒤, 최대 2초간 종료를 기다린다.
    /// 응답이 없으면 SIGKILL로 강제 종료한다.
    private func terminate(_ wrapper: VirtualDisplayProcess) async {
        let pid = wrapper.process.processIdentifier
        logger.info("terminate: identifier=\(wrapper.identifier) pid=\(pid)")

        guard wrapper.process.isRunning else { return }

        wrapper.process.terminate()  // SIGTERM

        // 100ms * 20 = 2s 폴링
        for _ in 0..<20 {
            if !wrapper.process.isRunning {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        if wrapper.process.isRunning {
            logger.warning("terminate: helper \(wrapper.identifier) ignored SIGTERM; escalating to SIGKILL")
            kill(pid, SIGKILL)
            for _ in 0..<10 {
                if !wrapper.process.isRunning { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// 번들된 helper 바이너리 URL을 해결한다.
    private static func resolveHelperURL() throws -> URL {
        guard let mainExecutable = Bundle.main.executableURL else {
            throw VirtualDisplayManagerError.helperNotFound(path: "<Bundle.main.executableURL is nil>")
        }
        let helperURL = mainExecutable
            .deletingLastPathComponent()
            .appendingPathComponent("nocvirtdisplay")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw VirtualDisplayManagerError.helperNotFound(path: helperURL.path)
        }
        return helperURL
    }

    /// FileHandle에서 첫 `\n` 직전까지의 UTF-8 문자열을 읽는다.
    /// 줄바꿈을 만나기 전에 EOF가 오면 throw. blocking I/O는 백그라운드 큐에서 실행된다.
    private static func readFirstLine(from handle: FileHandle) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        cont.resume(throwing: CocoaError(.fileReadUnknown))
                        return
                    }
                    buffer.append(chunk)
                    if let newlineIdx = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[..<newlineIdx]
                        cont.resume(returning: String(decoding: line, as: UTF8.self))
                        return
                    }
                }
            }
        }
    }
}
