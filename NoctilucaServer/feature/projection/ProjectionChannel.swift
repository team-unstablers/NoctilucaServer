//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit
import AppKit

class ProjectionChannel: Channel {
    let logger = NoctilucaLogger(category: "ProjectionChannel")

    override var serviceClass: ServiceClass { .userInput }

    private let cursorStateHolder = CursorStateHolder.shared
    let state = ProjectionChannelState()

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)

        assert(direction == .remote, "ProjectionChannel must be opened from remote side")
    }

    func destroy() async {
        guard let snapshot = await state.beginDestroy() else {
            return
        }

        for channel in snapshot.dataChannels {
            channel.projectionDelegate = nil
        }

        for session in snapshot.videoSessions {
            await session.stop()
        }

        for audioSession in snapshot.audioSessions {
            await audioSession.stop()
        }

        for channel in snapshot.dataChannels {
            do {
                try await channel.close()
            } catch {
                logger.warning("Failed to close projection data channel \(channel.identifier) during destroy: \(error)")
            }
        }

        snapshot.cursorSubscription?.destroy()
        snapshot.displaySubscription?.destroy()

        await state.completeDestroy()
    }

    private func cleanupTerminationTargets(
        _ targets: ProjectionChannelState.TerminationTargets,
        closeDataChannel: Bool
    ) async {
        if let videoSession = targets.videoSession {
            await videoSession.stop()
        }

        if let audioSession = targets.audioSession {
            await audioSession.stop()
        }

        guard closeDataChannel, let dataChannel = targets.dataChannel else {
            return
        }

        dataChannel.projectionDelegate = nil

        do {
            try await dataChannel.close()
        } catch {
            logger.warning("Failed to close projection data channel \(dataChannel.identifier): \(error)")
        }
    }

    private func handleProjectionDataChannelTermination(identifier: UUID, error: (any Error)? = nil) async {
        if let error {
            logger.warning("ProjectionDataChannel \(identifier) terminated with error: \(error)")
        }

        let targets = await state.terminateByDataChannelClosure(identifier: identifier)
        await cleanupTerminationTargets(targets, closeDataChannel: false)
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .projectionRequest:
            let projectionRequest = try ProjectionRequest.fromProtobufBytes(frame.data)
            await handleProjectionRequest(consume projectionRequest)

        case .stopProjectionRequest:
            let stopRequest = try StopProjectionRequest.fromProtobufBytes(frame.data)
            let targets = await state.terminateByControlMessage(
                identifier: stopRequest.identifier,
                kind: .video
            )
            await cleanupTerminationTargets(targets, closeDataChannel: true)

        case .projectionPerformanceReport:
            let report = try ProjectionPerformanceReport.fromProtobufBytes(frame.data)
            await handlePerformanceReport(report)

        case .subscribeCursorEventsRequest:
            let request = try SubscribeCursorEventsRequest.fromProtobufBytes(frame.data)
            try await handleSubscribeCursorEventsRequest(request)

        case .unsubscribeCursorEventsRequest:
            let request = try UnsubscribeCursorEventsRequest.fromProtobufBytes(frame.data)
            try await handleUnsubscribeCursorEventsRequest(request)

        case .audioProjectionRequest:
            let projectionRequest = try AudioProjectionRequest.fromProtobufBytes(frame.data)
            try await handleAudioProjectionRequest(consume projectionRequest)

        case .stopAudioProjectionRequest:
            let stopRequest = try StopAudioProjectionRequest.fromProtobufBytes(frame.data)
            let targets = await state.terminateByControlMessage(
                identifier: stopRequest.identifier,
                kind: .audio
            )
            await cleanupTerminationTargets(targets, closeDataChannel: true)

        case .displayListRequest:
            let request = try DisplayListRequest.fromProtobufBytes(frame.data)
            try await handleDisplayListRequest(request)

        case .subscribeDisplayChangesRequest:
            let request = try SubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await handleSubscribeDisplayChangesRequest(request)

        case .unsubscribeDisplayChangesRequest:
            let request = try UnsubscribeDisplayChangesRequest.fromProtobufBytes(frame.data)
            try await handleUnsubscribeDisplayChangesRequest(request)

        default:
            print("Unhandled opcode in ProjectionChannel: \(frame.opcode)")
        }
    }

    private func handlePerformanceReport(_ report: ProjectionPerformanceReport) async {
        guard let session = await state.sessionForPerformanceReport(identifier: report.identifier) else {
            logger.warning("Received performance report for unknown session \(report.identifier)")
            return
        }

        session.handlePerformanceReport(report)
    }

    func handleProjectionRequest(_ request: ProjectionRequest) async {
        guard let session = clientSession else {
            return
        }

        let identifier = request.identifier

        guard await state.reserveSession(identifier: identifier, kind: .video) else {
            logger.warning("Rejecting projection request for \(identifier) because lifecycle is not active or identifier is already in use")
            return
        }

        var transientSession: ProjectionSession?

        do {
            let projectionSettings = NoctilucaServer.shared.settings.projection
            let negotiator = CodecNegotiator.create(
                from: projectionSettings.codecNegotiationPolicy,
                specifications: projectionSettings.codecSpecifications
            )

            guard var negotiatedCodec = negotiator.negotiate(with: request.preferredCodecs) else {
                logger.error("Failed to negotiate codec for projection session \(identifier)")
                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: true)
                return
            }

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
            logger.info("Opened ProjectionDataChannel with id: \(openedChannel.identifier)")

            openedChannel.projectionDelegate = self

            guard await state.registerPendingDataChannel(identifier: identifier, channel: openedChannel) else {
                openedChannel.projectionDelegate = nil
                try? await openedChannel.close()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            let projectionSession = await ProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                preferredRecorderType: projectionSettings.preferredScreenRecorder
            )
            transientSession = projectionSession

            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()

            guard await state.activateVideoSession(identifier: identifier, session: projectionSession) else {
                projectionSession.dataChannel.projectionDelegate = nil
                await projectionSession.stop()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            try await send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: negotiatedCodec
            ))
        } catch {
            logger.error("Failed to handle projection request \(identifier): \(error)")

            if let transientSession {
                transientSession.dataChannel.projectionDelegate = nil
                await transientSession.stop()
            }

            let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
            await cleanupTerminationTargets(targets, closeDataChannel: true)
        }
    }

    private func handleSubscribeCursorEventsRequest(_ request: SubscribeCursorEventsRequest) async throws {
        let subscription = CursorEventSubscription()
        subscription.channel = self

        guard await state.addCursorSubscriptionIfAbsent(subscription) else {
            subscription.destroy()
            return
        }

        await subscription.setup()

        guard await state.isCurrentCursorSubscription(subscription) else {
            subscription.destroy()
            return
        }

        try await send(opcode: .subscribeCursorEventsResponse, message: SubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id
        ))
    }

    private func handleUnsubscribeCursorEventsRequest(_ request: UnsubscribeCursorEventsRequest) async throws {
        guard let subscription = await state.removeCursorSubscription() else {
            return
        }

        subscription.destroy()

        try await send(opcode: .unsubscribeCursorEventsResponse, message: UnsubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id,
            isSuccess: true
        ))
    }

    func sendCursorPositionEvent(_ state: CursorState) async throws {
        try await send(opcode: .cursorEvent, message: CursorEvent(
            event: .moveEvent(CursorMoveEvent(
                displayID: state.belongsTo,
                position: SRPoint(x: state.relativePosition.x, y: state.relativePosition.y)
            ))
        ))
    }

    func sendCursorImageEvent() async throws {
        guard let cursorImage = await cursorStateHolder.cursorImage,
              let cursorHotspot = await cursorStateHolder.cursorHotspot,
              let png = cursorImage.pngData()
        else {
            return
        }

        try await send(opcode: .cursorEvent, message: CursorEvent(
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
        guard let session = clientSession else {
            return
        }

        let identifier = request.identifier
        let projectionSettings = NoctilucaServer.shared.settings.projection

        guard projectionSettings.isAudioProjectionEnabled else {
            logger.warning("Audio projection request rejected because it is disabled in settings")
            try await send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                identifier: identifier,
                reason: .unknown,
                message: "Audio projection is disabled on server."
            ))
            return
        }

        guard await state.reserveSession(identifier: identifier, kind: .audio) else {
            logger.warning("Rejecting audio projection request for \(identifier) because lifecycle is not active or identifier is already in use")
            return
        }

        var transientSession: AudioProjectionSession?

        do {
            let serverSupportedCodecs = projectionSettings.audioCodecSpecifications.map { $0.fourCC }

            guard let negotiatedCodec = negotiateAudioCodec(
                clientPreferred: request.preferredCodecs,
                serverSupported: serverSupportedCodecs
            ) else {
                logger.warning("No supported audio codec found for session \(identifier)")
                try await send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                    identifier: identifier,
                    reason: .codecNotSupported,
                    message: "No supported audio codec found. Server supports: \(serverSupportedCodecs.map { $0.stringRepresentation }.joined(separator: ", "))"
                ))

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
                await cleanupTerminationTargets(targets, closeDataChannel: true)
                return
            }

            logger.info("Negotiated audio codec: \(negotiatedCodec.fourCC.stringRepresentation) for session \(identifier)")

            let openedChannel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            logger.info("Opened ProjectionDataChannel for audio with id: \(openedChannel.identifier)")

            openedChannel.projectionDelegate = self

            guard await state.registerPendingDataChannel(identifier: identifier, channel: openedChannel) else {
                openedChannel.projectionDelegate = nil
                try? await openedChannel.close()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            let projectionSession = AudioProjectionSession(
                id: identifier,
                dataChannel: openedChannel
            )
            transientSession = projectionSession

            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()

            guard await state.activateAudioSession(identifier: identifier, session: projectionSession) else {
                projectionSession.dataChannel.projectionDelegate = nil
                await projectionSession.stop()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            try await send(opcode: .audioSessionCreatedEvent, message: AudioSessionCreatedEvent(
                identifier: identifier,
                source: request.source,
                codec: negotiatedCodec
            ))
        } catch {
            logger.error("Failed to handle audio projection request \(identifier): \(error)")

            try? await send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                identifier: identifier,
                reason: .unknown,
                message: error.localizedDescription
            ))

            if let transientSession {
                transientSession.dataChannel.projectionDelegate = nil
                await transientSession.stop()
            }

            let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
            await cleanupTerminationTargets(targets, closeDataChannel: true)
        }
    }

    /// 클라이언트 선호 코덱 목록에서 서버가 지원하는 첫 번째 코덱을 선택
    private func negotiateAudioCodec(clientPreferred: [SiriusKit.AudioCodec], serverSupported: [CodecFourCC]) -> SiriusKit.AudioCodec? {
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

        case .singleWindow:
            fatalError("not implemented yet")

        default:
            return nil
        }
    }
}
