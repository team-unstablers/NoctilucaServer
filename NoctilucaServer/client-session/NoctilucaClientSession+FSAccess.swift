//
//  NoctilucaClientSession+FSAccess.swift
//  NoctilucaServer
//
//  fsaccess (consuming peer) 의 per-session 자동 wiring. 인증 완료 직후 호출되며,
//  settings.fileAccess.enabled / NFS 리스너 ready 상태에 따라:
//
//  1. NocFSAccessHost.shared.issueConnectionLabel + addConnection
//  2. fsaccess control channel 직접 open (handle.direction == .local)
//  3. List 요청 발신 → 응답 entries 보관
//  4. 모든 entry 자동 Mount + 해당 fsaccess_mount channel open + addMountSession.
//     access mode 는 settings.fileAccess.alwaysReadOnly 에 따라 read-only 또는
//     read-write 로 결정.
//
//  세션 종료 시 ``cleanupFSAccess`` 가 NocFSAccessHost.shared.removeConnection
//  으로 가상 트리에서 cascade 정리한다.
//

import Foundation
import Darwin

import SiriusKit

extension NoctilucaClientSession {
    private static let fsAccessLogger = SiriusLogger(
        category: "NoctilucaClientSession+FSAccess",
        subsystem: "app.noctiluca.server"
    )

    func setupFSAccessIfEnabled(uid: uid_t) async {
        let settings = await SettingsStore.shared.settings ?? AppSettings()
        guard settings.fileAccess.enabled else {
            return
        }
        guard let nfsPort = await NocFSAccessHost.shared.nfsPort, nfsPort > 0 else {
            Self.fsAccessLogger.warning("fsaccess: NFS listener is not ready — skipping fsaccess for this session.")
            return
        }
        let username = Self.usernameFor(uid: uid)
        let connectionLabel = await NocFSAccessHost.shared.issueConnectionLabel(username: username)
        await NocFSAccessHost.shared.addConnection(connectionLabel: connectionLabel, displayName: username)
        self.fsAccessConnectionLabel = connectionLabel

        do {
            let channel = try await session.channelManager.openChannel(
                for: .fileSystemAccess,
                identifier: ChannelIdentifier(),
                args: []
            )
            guard let fsAccessChannel = channel as? FSAccessChannel else {
                Self.fsAccessLogger.error("fsaccess: opened channel is not FSAccessChannel")
                await NocFSAccessHost.shared.removeConnection(connectionLabel: connectionLabel)
                self.fsAccessConnectionLabel = nil
                return
            }
            await fsAccessChannel.state.setConnectionLabel(connectionLabel)
            self.fsAccessChannel = fsAccessChannel
            Self.fsAccessLogger.info("fsaccess: control channel opened (label=\(connectionLabel))")

            await self.bootstrapFSAccessMounts(
                channel: fsAccessChannel,
                alwaysReadOnly: settings.fileAccess.alwaysReadOnly,
                connectionLabel: connectionLabel
            )
        } catch {
            Self.fsAccessLogger.error("fsaccess: openChannel(.fileSystemAccess) failed: \(error)")
            await NocFSAccessHost.shared.removeConnection(connectionLabel: connectionLabel)
            self.fsAccessConnectionLabel = nil
        }
    }

    func cleanupFSAccess() async {
        guard let connectionLabel = fsAccessConnectionLabel else { return }
        await NocFSAccessHost.shared.removeConnection(connectionLabel: connectionLabel)
        self.fsAccessConnectionLabel = nil
        self.fsAccessChannel = nil
    }

    // MARK: - Auto-mount

    private func bootstrapFSAccessMounts(channel: FSAccessChannel,
                                         alwaysReadOnly: Bool,
                                         connectionLabel: String) async {
        let listResponse: FileSystemListResponse
        do {
            listResponse = try await channel.requestList()
        } catch {
            Self.fsAccessLogger.error("fsaccess: requestList failed: \(error)")
            return
        }
        guard listResponse.success else {
            Self.fsAccessLogger.warning("fsaccess: List returned success=false: \(listResponse.error?.message ?? "")")
            return
        }
        await channel.state.setEntries(listResponse.entries)

        let access: AccessMode = alwaysReadOnly ? .read : .readWrite

        for entry in listResponse.entries {
            await self.autoMountEntry(
                channel: channel,
                connectionLabel: connectionLabel,
                entry: entry,
                requestedAccess: access
            )
        }
    }

    private func autoMountEntry(channel: FSAccessChannel,
                                connectionLabel: String,
                                entry: FileSystemEntry,
                                requestedAccess: AccessMode) async {
        let mountResponse: FileSystemMountResponse
        do {
            mountResponse = try await channel.requestMount(
                entryId: entry.id,
                requestedAccess: requestedAccess,
                reason: "host auto-mount (access=\(requestedAccess))"
            )
        } catch {
            Self.fsAccessLogger.error("fsaccess: auto-mount throw for '\(entry.name)': \(error)")
            return
        }
        guard mountResponse.success else {
            Self.fsAccessLogger.warning("fsaccess: auto-mount of '\(entry.name)' failed: \(mountResponse.error?.message ?? "")")
            return
        }

        let added = await NocFSAccessHost.shared.addMountSession(
            connectionLabel: connectionLabel,
            mountSessionId: mountResponse.sessionId,
            displayName: entry.name,
            grantedAccess: mountResponse.grantedAccess.rawValue
        )
        guard added else {
            Self.fsAccessLogger.error("fsaccess: addMountSession returned false for '\(entry.name)'")
            return
        }

        do {
            let mountChannel = try await session.channelManager.openChannel(
                for: .fileSystemAccessMount,
                identifier: ChannelIdentifier(),
                args: FSAccessMountChannelArgs.encode(sessionId: mountResponse.sessionId)
            )
            guard let fsMountChannel = mountChannel as? FSAccessMountChannel else {
                Self.fsAccessLogger.error("fsaccess: opened mount channel is not FSAccessMountChannel")
                await NocFSAccessHost.shared.removeMountSession(mountResponse.sessionId)
                return
            }
            // capability flag 를 mount channel 자체에 저장 — NFS lock callback
            // dispatch 에서 supportsLocks 분기 판단에 사용.
            fsMountChannel.supportsLocks = mountResponse.supportsLocks
            let record = FSAccessMountSessionRecord(
                id: mountResponse.sessionId,
                connectionLabel: connectionLabel,
                entry: entry,
                grantedAccess: mountResponse.grantedAccess,
                supportsLocks: mountResponse.supportsLocks
            )
            await channel.state.addMountSession(record)
            Self.fsAccessLogger.info("fsaccess: auto-mounted '\(entry.name)' (session=\(mountResponse.sessionId.uuidString) granted=\(mountResponse.grantedAccess.rawValue) supportsLocks=\(mountResponse.supportsLocks))")
        } catch {
            Self.fsAccessLogger.error("fsaccess: openChannel(.fileSystemAccessMount) failed for '\(entry.name)': \(error)")
            await NocFSAccessHost.shared.removeMountSession(mountResponse.sessionId)
        }
    }

    // MARK: - Helpers

    private static func usernameFor(uid: uid_t) -> String {
        guard let pw = getpwuid(uid), let cstr = pw.pointee.pw_name else {
            return "uid-\(uid)"
        }
        return String(cString: cstr)
    }
}
