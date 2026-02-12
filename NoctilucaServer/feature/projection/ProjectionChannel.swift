//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit
import AppKit

import Atomics

class ProjectionChannel: Channel {
    let logger = NoctilucaLogger(category: "ProjectionChannel")
    
    override var serviceClass: ServiceClass { .userInput }

    private let cursorStateHolder = CursorStateHolder.shared
    private var subscription: CursorEventSubscription? = nil

    /// Display 변경 이벤트 구독
    var displaySubscription: DisplayEventSubscription? = nil

    private(set) var sessions: [UUID: ProjectionSession] = [:]
    private(set) var audioSessions: [UUID: AudioProjectionSession] = [:]

    /// 모든 ProjectionDataChannel 추적 (orphan 채널 정리용)
    private(set) var projectionDataChannels: [UUID: ProjectionDataChannel] = [:]
    
    private let isDestroyed = ManagedAtomic<Bool>(false)

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
        
        assert(direction == .remote, "ProjectionChannel must be opened from remote side")
    }
    
    func destroy() async {
        let result = self.isDestroyed.compareExchange(expected: false, desired: true, ordering: .relaxed)
        guard result.exchanged else {
            return
        }
        
        // 비디오 프로젝션 세션 정리
        for (id, session) in self.sessions {
            do {
                try await session.stop()
            } catch {
                self.logger.error("Failed to stop projection session \(session.id): \(error)")
            }
            self.projectionDataChannels.removeValue(forKey: id)
        }
        self.sessions.removeAll()

        // 오디오 프로젝션 세션 정리
        for (id, audioSession) in self.audioSessions {
            do {
                try await audioSession.stop()
            } catch {
                self.logger.error("Failed to stop audio projection session \(audioSession.id): \(error)")
            }
            self.projectionDataChannels.removeValue(forKey: id)
        }
        self.audioSessions.removeAll()

        // orphan ProjectionDataChannel 강제 정리
        // 세션에 등록되지 않았거나 세션 stop()에서 정리되지 않은 채널들
        for channel in self.projectionDataChannels.values {
            do {
                try await channel.close()
            } catch {
                self.logger.error("Failed to close orphan projection data channel \(channel.identifier): \(error)")
            }
        }
        self.projectionDataChannels.removeAll()

        // cursor subscription 정리
        self.subscription?.destroy()
        self.subscription = nil

        // display subscription 정리
        self.displaySubscription?.destroy()
        self.displaySubscription = nil
    }

    private func handleProjectionDataChannelTermination(identifier: UUID, error: (any Error)? = nil) async {
        if let error {
            self.logger.warning("ProjectionDataChannel \(identifier) terminated with error: \(error)")
        }

        // 추적 딕셔너리에서 제거
        self.projectionDataChannels.removeValue(forKey: identifier)

        if let session = self.sessions.removeValue(forKey: identifier) {
            do {
                try await session.stop()
            } catch {
                self.logger.error("Failed to stop projection session \(session.id): \(error)")
            }
        }

        if let audioSession = self.audioSessions.removeValue(forKey: identifier) {
            do {
                try await audioSession.stop()
            } catch {
                self.logger.error("Failed to stop audio projection session \(audioSession.id): \(error)")
            }
        }
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .projectionRequest:
            let projectionRequest = try ProjectionRequest.fromProtobufBytes(frame.data)
            await self.handleProjectionRequest(consume projectionRequest)
        case .stopProjectionRequest:
            let stopRequest = try StopProjectionRequest.fromProtobufBytes(frame.data)
            if let session = self.sessions.removeValue(forKey: stopRequest.identifier) {
                try? await session.stop()
            }
            self.projectionDataChannels.removeValue(forKey: stopRequest.identifier)
        case .projectionPerformanceReport:
            let report = try ProjectionPerformanceReport.fromProtobufBytes(frame.data)
            await self.handlePerformanceReport(report)
        case .subscribeCursorEventsRequest:
            let request = try SubscribeCursorEventsRequest.fromProtobufBytes(frame.data)
            try await self.handleSubscribeCursorEventsRequest(request)
        case .unsubscribeCursorEventsRequest:
            let request = try UnsubscribeCursorEventsRequest.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeCursorEventsRequest(request)
            
        case .audioProjectionRequest:
            let projectionRequest = try AudioProjectionRequest.fromProtobufBytes(frame.data)
            try await self.handleAudioProjectionRequest(consume projectionRequest)
        case .stopAudioProjectionRequest:
            let stopRequest = try StopAudioProjectionRequest.fromProtobufBytes(frame.data)
            if let session = self.audioSessions.removeValue(forKey: stopRequest.identifier) {
                await session.stop()
            }
            self.projectionDataChannels.removeValue(forKey: stopRequest.identifier)

        // displayman opcodes
        case .displayListRequest:
            let request = try DisplayListRequest.fromProtobufBytes(frame.data)
            try await self.handleDisplayListRequest(request)
        case .subscribeDisplayChangesRequest:
            let request = try SubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await self.handleSubscribeDisplayChangesRequest(request)
        case .unsubscribeDisplayChangesRequest:
            let request = try UnsubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await self.handleUnsubscribeDisplayChangesRequest(request)

        default:
            print("Unhandled opcode in ProjectionChannel: \(frame.opcode)")
            break
        }
    }
    
    private func handlePerformanceReport(_ report: ProjectionPerformanceReport) async {
        guard let session = self.sessions[report.identifier] else {
            self.logger.warning("Received performance report for unknown session \(report.identifier)")
            return
        }
        
        session.handlePerformanceReport(report)
    }
    
    func handleProjectionRequest(_ request: ProjectionRequest) async {
        guard let session = self.clientSession else {
            return
        }

        var channel: ProjectionDataChannel?
        do {
            let identifier = request.identifier

            let projectionSettings = NoctilucaServer.shared.settings.projection
            let negotiator = CodecNegotiator.create(
                from: projectionSettings.codecNegotiationPolicy,
                specifications: projectionSettings.codecSpecifications
            )

            var negotiatedCodec = negotiator.negotiate(with: request.preferredCodecs)

            guard var negotiatedCodec else {
                fatalError("Failed to negotiate codec for projection session")
            }

            // FIXME
            if let desiredSize = request.preferredCodecs.compactMap({ $0.size }).first {
                negotiatedCodec = Codec(
                    fourCC: negotiatedCodec.fourCC,
                    frameRate: negotiatedCodec.frameRate,
                    size: desiredSize,
                    options: negotiatedCodec.options,
                    quality: negotiatedCodec.quality
                )
            } else {
                let contentSize = await request.viewport.contentSize

                negotiatedCodec = Codec(
                    fourCC: negotiatedCodec.fourCC,
                    frameRate: negotiatedCodec.frameRate,
                    size: contentSize,
                    options: negotiatedCodec.options,
                    quality: negotiatedCodec.quality
                )
            }

            let openedChannel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            channel = openedChannel

            self.logger.info("Opened ProjectionDataChannel with id: \(openedChannel.identifier)")
            openedChannel.projectionDelegate = self
            self.projectionDataChannels[identifier] = openedChannel

            let projectionSession = await ProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                preferredRecorderType: projectionSettings.preferredScreenRecorder
            )

            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()

            self.sessions[identifier] = projectionSession

            try await self.send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: negotiatedCodec
            ))
        } catch {
            self.logger.error("Failed to handle projection request: \(error)")
            if let channel {
                try? await channel.close()
                self.projectionDataChannels.removeValue(forKey: channel.identifier)
            }
        }
    }
    
    private func handleSubscribeCursorEventsRequest(_ request: SubscribeCursorEventsRequest) async throws {
        if let subscription = self.subscription {
            // TODO: send error
            return
        }
        
        let subscription = CursorEventSubscription()
        subscription.channel = self
        
        await subscription.setup()
        
        self.subscription = subscription
        
        try await self.send(opcode: .subscribeCursorEventsResponse, message: SubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id
        ))
    }
    
    private func handleUnsubscribeCursorEventsRequest(_ request: UnsubscribeCursorEventsRequest) async throws {
        guard let subscription = self.subscription else {
            // TODO: send error
            return
        }
        
        subscription.destroy()
        self.subscription = nil

        try await self.send(opcode: .unsubscribeCursorEventsResponse, message: UnsubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id,
            isSuccess: true
        ))
    }
    
    func sendCursorPositionEvent(_ state: CursorState) async throws {
        /// STOP!: position은 (하단, 좌측) 기준입니다. 이를 (상단, 좌측) 기준으로 변환해야 합니다.
        ///        아니, 그건 그런데, 이거 position이 그래픽 세션의 전체 뷰포트 (모든 모니터를 합친) 인지, 아니면 특정 모니터 기준인지도 확실하지가 않은데...
        let displayLayoutManager = DisplayLayoutManager.shared
        
        try await self.send(opcode: .cursorEvent, message: CursorEvent(
            event: .moveEvent(CursorMoveEvent(
                displayID: state.belongsTo,
                position: SRPoint(x: state.relativePosition.x, y: state.relativePosition.y)
            ))
        ))
    }
    
    func sendCursorImageEvent() async throws {
        guard let cursorImage   = await cursorStateHolder.cursorImage,
              let cursorHotspot = await cursorStateHolder.cursorHotspot,
              let png = cursorImage.pngData()
        else {
            return
        }
        
        
        try await self.send(opcode: .cursorEvent, message: CursorEvent(
            event: .imageEvent(CursorImageEvent(
                cursorType: UInt64(cursorStateHolder.cursorHash),
                mimeType: "image/png",
                size: SRSize(width: cursorImage.size.width, height: cursorImage.size.height),
                hotspot: SRPoint(x: cursorHotspot.x, y: cursorHotspot.y),
                imageData: png
            ))
        ))
    }
    
    private func handleAudioProjectionRequest(_ request: AudioProjectionRequest) async throws {
        guard let session = self.clientSession else {
            return
        }

        let identifier = request.identifier
        let projectionSettings = NoctilucaServer.shared.settings.projection

        guard projectionSettings.isAudioProjectionEnabled else {
            self.logger.warning("Audio projection request rejected because it is disabled in settings")
            try await self.send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                identifier: identifier,
                reason: .unknown,
                message: "Audio projection is disabled on server."
            ))
            return
        }

        var channel: ProjectionDataChannel?
        do {
            let serverSupportedCodecs = projectionSettings.audioCodecSpecifications.map { $0.fourCC }

            // 코덱 협상: 클라이언트 선호 코덱 중 서버가 지원하는 첫 번째 코덱 선택
            guard let negotiatedCodec = negotiateAudioCodec(clientPreferred: request.preferredCodecs, serverSupported: serverSupportedCodecs) else {
                self.logger.warning("No supported audio codec found for session \(identifier)")
                try await self.send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                    identifier: identifier,
                    reason: .codecNotSupported,
                    message: "No supported audio codec found. Server supports: \(serverSupportedCodecs.map { $0.stringRepresentation }.joined(separator: ", "))"
                ))
                return
            }

            self.logger.info("Negotiated audio codec: \(negotiatedCodec.fourCC.stringRepresentation) for session \(identifier)")

            let openedChannel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            channel = openedChannel

            self.logger.info("Opened ProjectionDataChannel for audio with id: \(openedChannel.identifier)")
            openedChannel.projectionDelegate = self
            self.projectionDataChannels[identifier] = openedChannel

            let projectionSession = AudioProjectionSession(
                id: identifier,
                dataChannel: openedChannel
            )

            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()

            self.audioSessions[identifier] = projectionSession

            try await self.send(opcode: .audioSessionCreatedEvent, message: AudioSessionCreatedEvent(
                identifier: identifier,
                source: request.source,
                codec: negotiatedCodec
            ))
        } catch {
            self.logger.error("Failed to handle audio projection request: \(error)")

            // 세션 생성 실패 이벤트 전송
            try? await self.send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                identifier: identifier,
                reason: .unknown,
                message: error.localizedDescription
            ))

            if let channel {
                try? await channel.close()
                self.projectionDataChannels.removeValue(forKey: channel.identifier)
            }
        }
    }

    /// 클라이언트 선호 코덱 목록에서 서버가 지원하는 첫 번째 코덱을 선택
    private func negotiateAudioCodec(clientPreferred: [SiriusKit.AudioCodec], serverSupported: [CodecFourCC]) -> SiriusKit.AudioCodec? {
        // 클라이언트 선호 순서대로 서버 지원 여부 확인
        for codec in clientPreferred {
            if serverSupported.contains(codec.fourCC) {
                return codec
            }
        }
        return nil
    }
}

extension ProjectionChannel: ProjectionDataChannelDelegate {
    func projectionDataChannelDidClose(_ channel: ProjectionDataChannel) {
        Task { [weak self] in
            await self?.handleProjectionDataChannelTermination(identifier: channel.identifier)
        }
    }

    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error) {
        Task { [weak self] in
            await self?.handleProjectionDataChannelTermination(identifier: channel.identifier, error: error)
        }
    }
}


fileprivate extension ProjectionSource {
    @MainActor
    var contentSize: SRSize? {
        switch value {
        case .entireDisplay(let source):
            let layoutManager = DisplayLayoutManager.shared
            let displayID = switch (source.displayID) {
            case -1:
                layoutManager.displayLayouts.keys.first { CGDisplayIsMain($0) != 0 }!
            case -2:
                fatalError("entire display layout is not supported yet")
            default:
                CGDirectDisplayID(source.displayID)
            }
            
            if let displaySize = DisplayLayoutManager.shared.displayLayouts[displayID]?.frame.size {
                return SRSize(width: displaySize.width, height: displaySize.height)
            } else {
                return nil
            }
            
        case .region(let region):
            return SRSize(width: region.region.width, height: region.region.height)
            
        case .singleWindow(let window):
            fatalError("not implemented yet")
            
        default:
            return nil
        }
    }
}
