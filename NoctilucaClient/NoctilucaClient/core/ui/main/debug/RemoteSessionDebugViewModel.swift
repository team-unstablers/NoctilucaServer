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
class RemoteSessionDebugViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    private var pollingTask: Task<Void, Never>?

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
        // Projection 구독
        session.$projection
            .sink { [weak self] projection in
                self?.subscribeProjection(projection)
            }
            .store(in: &cancellables)

        // HIDIO 구독
        session.$hidio
            .sink { [weak self] hidio in
                self?.subscribeHIDIO(hidio)
            }
            .store(in: &cancellables)
    }

    private func subscribeProjection(_ projection: RemoteSession.Projection?) {
        // 기존 구독 정리 (projection 관련만)
        cancellables = cancellables.filter { _ in true } // keep all, re-subscribe below

        guard let projection else {
            self.videoSessions = []
            self.audioSessions = []
            return
        }

        projection.$projectionSessions
            .receive(on: RunLoop.main)
            .sink { [weak self, weak projection] sessions in
                self?.updateVideoSessions(sessions, projection: projection)
            }
            .store(in: &cancellables)

        projection.$audioSessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                self?.audioSessions = sessions.values.map { session in
                    AudioSessionDebugInfo(
                        id: session.id,
                        codec: session.debugSnapshot.codec
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func updateVideoSessions(_ sessions: [UUID: ProjectionSession], projection: RemoteSession.Projection?) {
        self.videoSessions = sessions.values.map { session in
            let refCount = projection?.projectionSessionReferences[session.id]?.load(ordering: .relaxed) ?? 0
            let snapshot = session.debugSnapshot
            return VideoSessionDebugInfo(
                id: session.id,
                displayID: -42,
                codec: snapshot.codec,
                size: snapshot.size,
                decoderTypeName: snapshot.decoderTypeName,
                dataRateKbps: session.currentDataRateKbps,
                referenceCount: refCount
            )
        }
    }

    private func subscribeHIDIO(_ hidio: RemoteSession.HIDIO?) {
        guard let hidio else {
            self.hidioSessionMode = .shared
            self.hidioSessionState = .inactive
            self.pressedKeys = []
            return
        }

        hidio.$sessionMode
            .receive(on: RunLoop.main)
            .assign(to: &$hidioSessionMode)

        hidio.$sessionState
            .receive(on: RunLoop.main)
            .assign(to: &$hidioSessionState)

        hidio.controller.keyStateDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                self?.pressedKeys = keys
            }
            .store(in: &cancellables)
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
