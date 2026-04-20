//
//  RemoteSessionDebugViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import Foundation
import Combine
import Atomics

import SiriusKitCore
import SiriusKitClient

// MARK: - Debug Info Models

struct ChannelDebugInfo: Identifiable {
    let id: UUID
    let featureName: String
    let featureID: UUID?
    let serviceClass: ServiceClass
    let direction: ChannelDirection
    let uplinkDataRate: Double   // bytes/sec
    let downlinkDataRate: Double // bytes/sec
}

struct VideoSessionDebugInfo: Identifiable {
    let id: UUID
    let displayID: Int
    let codec: Codec?
    let size: CGSize
    let decoderTypeName: String
    let dataRateKbps: Double
    let referenceCount: Int
}

struct AudioSessionDebugInfo: Identifiable {
    let id: UUID
    let codec: AudioCodec?
}

// MARK: - ViewModel

@MainActor
final class RemoteSessionDebugViewModel: ObservableObject {
    private var pollingTask: Task<Void, Never>?

    /// HIDIO의 `keyStateDidChange`(Combine Publisher)는 `@Observable` 대상이 아니므로
    /// `hidio` 인스턴스가 교체될 때마다 이 cancellable을 갈아끼운다.
    private var keyStateCancellable: AnyCancellable?

    private weak var remoteSession: RemoteSession?

    // MARK: - Channels Tab

    @Published
    private(set) var channels: [ChannelDebugInfo] = []

    @Published
    var selectedChannelID: UUID?

    var selectedChannel: ChannelDebugInfo? {
        guard let id = selectedChannelID else { return nil }
        return channels.first { $0.id == id }
    }

    // MARK: - Projection Tab

    @Published
    private(set) var videoSessions: [VideoSessionDebugInfo] = []

    @Published
    private(set) var audioSessions: [AudioSessionDebugInfo] = []

    @Published
    var selectedProjectionSessionID: UUID?

    var selectedVideoSession: VideoSessionDebugInfo? {
        guard let id = selectedProjectionSessionID else { return nil }
        return videoSessions.first { $0.id == id }
    }

    // MARK: - HIDIO Tab

    @Published
    private(set) var hidioSessionMode: HIDIOSessionMode = .shared

    @Published
    private(set) var hidioSessionState: HIDIOSessionState = .inactive

    @Published
    private(set) var pressedKeys: Set<LinuxKeycode> = []

    // MARK: - Lifecycle

    init(remoteSession: RemoteSession) {
        self.remoteSession = remoteSession
        subscribe(to: remoteSession)
        startChannelPolling()
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Subscriptions

    private func subscribe(to session: RemoteSession) {
        // projection.projectionSessions 자동 갱신.
        // session.projection 자체 또는 내부 projectionSessions가 바뀌면 observe가 재실행된다.
        observeChanges { [weak self, weak session] in
            guard let self, let session else {
                self?.videoSessions = []
                return
            }
            if let projection = session.projection {
                self.updateVideoSessions(projection.projectionSessions, projection: projection)
            } else {
                self.videoSessions = []
            }
        }

        // projection.audioSessions 자동 갱신.
        observeChanges { [weak self, weak session] in
            guard let self, let session else {
                self?.audioSessions = []
                return
            }
            if let projection = session.projection {
                self.audioSessions = projection.audioSessions.values.map { audioSession in
                    AudioSessionDebugInfo(
                        id: audioSession.id,
                        codec: audioSession.debugSnapshot.codec
                    )
                }
            } else {
                self.audioSessions = []
            }
        }

        // hidio.sessionMode
        observeChanges { [weak self, weak session] in
            guard let self, let session else { return }
            self.hidioSessionMode = session.hidio?.sessionMode ?? .shared
        }

        // hidio.sessionState
        observeChanges { [weak self, weak session] in
            guard let self, let session else { return }
            self.hidioSessionState = session.hidio?.sessionState ?? .inactive
        }

        // hidio 인스턴스 교체 감지 → keyStateDidChange(Combine) 재구독.
        observeChanges { [weak self, weak session] in
            guard let self, let session else {
                self?.rebindKeyState(to: nil)
                return
            }
            self.rebindKeyState(to: session.hidio)
        }
    }

    private func updateVideoSessions(_ sessions: [UUID: ProjectionSession], projection: RemoteSession.Projection?) {
        self.videoSessions = sessions.values.map { session in
            let refCount = projection?.projectionSessionReferences[session.id]?.load(ordering: .relaxed) ?? 0
            let snapshot = session.debugSnapshot
            return VideoSessionDebugInfo(
                id: session.id,
                displayID: session.displayID,
                codec: snapshot.codec,
                size: snapshot.size,
                decoderTypeName: snapshot.decoderTypeName,
                dataRateKbps: session.currentDataRateKbps,
                referenceCount: refCount
            )
        }
    }

    private func rebindKeyState(to hidio: RemoteSession.HIDIO?) {
        keyStateCancellable?.cancel()
        keyStateCancellable = nil

        guard let hidio else {
            self.pressedKeys = []
            return
        }

        keyStateCancellable = hidio.controller.keyStateDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                self?.pressedKeys = keys
            }
    }

    // MARK: - Channel Polling (1초)

    private func startChannelPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollChannels()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func pollChannels() async {
        guard let session = remoteSession?.client.session else { return }
        let channelMap = await session.channelManager.channels

        self.channels = channelMap.values.map { channel in
            let featureName: String
            let feature = channel.handle.feature
            featureName = Self.featureDisplayName(feature)

            return ChannelDebugInfo(
                id: channel.identifier,
                featureName: featureName,
                featureID: feature.rawValue,
                serviceClass: channel.handle.serviceClass,
                direction: channel.handle.direction,
                uplinkDataRate: channel.handle.uplinkDataRate,
                downlinkDataRate: channel.handle.downlinkDataRate
            )
        }.sorted { $0.featureName < $1.featureName }
    }

    // MARK: - Actions

    func killChannel(_ channelID: UUID) {
        guard let session = remoteSession?.client.session else { return }
        Task {
            let channel = await session.channelManager.channels[channelID]
            try? await channel?.handle.close()
        }
    }

    func killProjectionSession(_ sessionID: UUID) async {
        guard let projection = remoteSession?.projection else { return }
        if let session = projection.projectionSessions[sessionID] {
            try? await session.stop()
        }
    }

    // MARK: - Helpers

    private static func featureDisplayName(_ feature: SiriusFeature) -> String {
        switch feature {
        case .hidio: return "hidio"
        case .projection: return "projection"
        case .projectionData: return "projectionData"
        case .clipboard: return "clipboard"
        case .transfer: return "transfer"
        default: return feature.rawValue.uuidString.prefix(8).lowercased()
        }
    }
}
