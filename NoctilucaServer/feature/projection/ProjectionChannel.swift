//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit
import AppKit

final class ProjectionChannel: Channel, ChannelEventConsumer {
    let logger = NoctilucaLogger(category: "ProjectionChannel")

    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .userInput

    let state = ProjectionChannelState()
    
    @MainActor
    var desktopContextManager: DesktopContextManager {
        DesktopContextManager.shared
    }
    

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음. (Rule I 패턴 2)
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        assert(handle.direction == .remote,
               "ProjectionChannel must be opened from remote side")

        // DisplayLayoutManager disconnect sink 를 state actor 내부로 설치.
        // Combine cancellable 은 actor 내부 저장 → Sendable 적합 (Rule J).
        Task { [state] in
            await state.installDisplayDisconnectSink { displayID in
                Task { [weak self] in
                    await self?.handleDisplayDisconnected(displayID: displayID)
                }
            }
        }

        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer
    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .projectionRequest:
            let projectionRequest = try ProjectionRequest.fromProtobufBytes(frame.data)
            await handleProjectionRequest(consume projectionRequest)

        case .stopProjectionRequest:
            let stopRequest = try StopProjectionRequest.fromProtobufBytes(frame.data)
            let identifier = stopRequest.identifier
            let targets = await state.terminateByControlMessage(
                identifier: identifier,
                kind: .video
            )
            await cleanupTerminationTargets(targets, closeDataChannel: true)

            // 클라이언트 요청에 의한 정상 종료임을 명시적으로 알림.
            // 이 신호가 없으면 dataChannel close race 로 handleProjectionDataChannelTermination
            // 경로를 타게 되어 reason=.unknown 이 보내지고, 클라이언트가 자동 재시도(backoff)를
            // 발동하는 회귀가 발생함. cleanupTerminationTargets 가 setDelegate(nil) 을 먼저 수행
            // 하므로 후속 close 콜백에 의한 EndedEvent 중복 송신은 차단된다.
            if targets.videoSession != nil || targets.dataChannel != nil {
                do {
                    try await handle.send(opcode: .projectionSessionEndedEvent, message: ProjectionSessionEndedEvent(
                        identifier: identifier,
                        reason: VideoSessionEndReason.clientRequested,
                        message: nil
                    ))
                } catch {
                    logger.warning("Failed to send ProjectionSessionEndedEvent for session \(identifier) after client stop request: \(error)")
                }
            }

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

        case .displayTransactionRequest:
            let request = try DisplayTransactionRequest.fromProtobufBytes(frame.data)
            try await handleDisplayTransactionRequest(request)

        // MARK: Window Management (Query)
        case .windowListRequest:
            let request = try WindowListRequest.fromProtobufBytes(frame.data)
            try await handleWindowListRequest(request)

        case .getWindowInfoRequest:
            let request = try GetWindowInfoRequest.fromProtobufBytes(frame.data)
            try await handleGetWindowInfoRequest(request)

        case .getWindowIconRequest:
            let request = try GetWindowIconRequest.fromProtobufBytes(frame.data)
            try await handleGetWindowIconRequest(request)

        case .getWindowThumbnailRequest:
            let request = try GetWindowThumbnailRequest.fromProtobufBytes(frame.data)
            try await handleGetWindowThumbnailRequest(request)

        case .subscribeWindowEventsRequest:
            let request = try SubscribeWindowEventsRequest.fromProtobufBytes(frame.data)
            try await handleSubscribeWindowEventsRequest(request)

        case .unsubscribeWindowEventsRequest:
            let request = try UnsubscribeWindowEventsRequest.fromProtobufBytes(frame.data)
            try await handleUnsubscribeWindowEventsRequest(request)

        // MARK: Window Management (Manipulation)
        case .windowManipulationRequest:
            let request = try WindowManipulationRequest.fromProtobufBytes(frame.data)
            try await handleWindowManipulationRequest(request)

        // MARK: Application Management (AppMan)
        case .applicationListRequest:
            let request = try ApplicationListRequest.fromProtobufBytes(frame.data)
            try await handleApplicationListRequest(request)

        case .applicationLaunchRequest:
            let request = try ApplicationLaunchRequest.fromProtobufBytes(frame.data)
            try await handleApplicationLaunchRequest(request)

        case .applicationTerminateRequest:
            let request = try ApplicationTerminateRequest.fromProtobufBytes(frame.data)
            try await handleApplicationTerminateRequest(request)

        case .subscribeApplicationEventsRequest:
            let request = try SubscribeApplicationEventsRequest.fromProtobufBytes(frame.data)
            try await handleSubscribeApplicationEventsRequest(request)

        case .unsubscribeApplicationEventsRequest:
            let request = try UnsubscribeApplicationEventsRequest.fromProtobufBytes(frame.data)
            try await handleUnsubscribeApplicationEventsRequest(request)

        case .startAppStreamRequest:
            let request = try StartAppStreamRequest.fromProtobufBytes(frame.data)
            try await handleStartAppStreamRequest(request)

        case .stopAppStreamRequest:
            let request = try StopAppStreamRequest.fromProtobufBytes(frame.data)
            try await handleStopAppStreamRequest(request)

        // MARK: Accessibility
        case .getAccessibilityTreeRequest:
            let request = try GetAccessibilityTreeRequest.fromProtobufBytes(frame.data)
            try await handleGetAccessibilityTreeRequest(request)

        case .subscribeAccessibilityTreeUpdatesRequest:
            let request = try SubscribeAccessibilityTreeUpdatesRequest.fromProtobufBytes(frame.data)
            try await handleSubscribeAccessibilityTreeUpdatesRequest(request)

        case .unsubscribeAccessibilityTreeUpdatesRequest:
            let request = try UnsubscribeAccessibilityTreeUpdatesRequest.fromProtobufBytes(frame.data)
            try await handleUnsubscribeAccessibilityTreeUpdatesRequest(request)

        case .dispatchActionRequest:
            let request = try DispatchActionRequest.fromProtobufBytes(frame.data)
            try await handleDispatchActionRequest(request)

        default:
            logger.warning("Unhandled opcode in ProjectionChannel: \(frame.opcode)")
        }
    }

    func handleError(error: any Error) async {
        await destroy()
    }

    func handleStreamClose() async {
        await destroy()
    }

    // MARK: - Destroy / Cleanup

    func destroy() async {
        let sessionID = clientSession?.id

        guard let snapshot = await state.beginDestroy() else {
            return
        }

        for channel in snapshot.dataChannels {
            await channel.state.setDelegate(nil)
        }

        for session in snapshot.videoSessions {
            await session.stop()
        }

        for audioSession in snapshot.audioSessions {
            await audioSession.stop()
        }

        for channel in snapshot.dataChannels {
            do {
                try await channel.handle.close()
            } catch {
                logger.warning("Failed to close projection data channel \(channel.identifier) during destroy: \(error)")
            }
        }

        snapshot.cursorSubscription?.destroy()
        snapshot.displaySubscription?.destroy()
        
        if let appEventSubId = snapshot.appEventSubscriptionId {
            let desktopContextManager = await DesktopContextManager.shared
            _ = await desktopContextManager.unsubscribeAppEvents(id: appEventSubId)
        }

        if !snapshot.accessibilitySubscriptions.isEmpty {
            let desktopContextManager = await DesktopContextManager.shared
            for subscription in snapshot.accessibilitySubscriptions {
                await desktopContextManager.unsubscribeMenuEvents(id: subscription.menuEventHandlerId)
                await desktopContextManager.unsubscribeContextMenuEvents(id: subscription.contextMenuEventHandlerId)
            }
        }

        if let appStreamSession = snapshot.appStreamSession {
            await cleanupAppStreamSession(appStreamSession)
        }

        let layoutManager = await DisplayLayoutManager.shared
        for handle in snapshot.virtualDisplayHandles {
            await layoutManager.destroyVirtualDisplay(handle)
        }
        if let sessionID {
            await layoutManager.destroyAllVirtualDisplays(ownedBy: sessionID)
        }

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

        await dataChannel.state.setDelegate(nil)

        do {
            try await dataChannel.handle.close()
        } catch {
            logger.warning("Failed to close projection data channel \(dataChannel.identifier): \(error)")
        }
    }

    private func handleDisplayDisconnected(displayID: CGDirectDisplayID) async {
        let affectedIdentifiers = await state.videoSessionIdentifiers(forDisplayID: displayID)

        guard !affectedIdentifiers.isEmpty else { return }

        logger.warning("Display \(displayID) disconnected, terminating \(affectedIdentifiers.count) affected projection session(s)")

        for identifier in affectedIdentifiers {
            let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
            await cleanupTerminationTargets(targets, closeDataChannel: true)

            do {
                try await handle.send(opcode: .projectionSessionEndedEvent, message: ProjectionSessionEndedEvent(
                    identifier: identifier,
                    reason: VideoSessionEndReason.displayDisconnected,
                    message: "Display disconnected"
                ))
            } catch {
                logger.warning("Failed to send ProjectionSessionEndedEvent for session \(identifier): \(error)")
            }
        }
    }

    private func handleProjectionDataChannelTermination(identifier: UUID, error: (any Error)? = nil) async {
        if let error {
            logger.warning("ProjectionDataChannel \(identifier) terminated with error: \(error)")
        }

        let targets = await state.terminateByDataChannelClosure(identifier: identifier)
        await cleanupTerminationTargets(targets, closeDataChannel: false)

        let reason: VideoSessionEndReason = error != nil ? .dataChannelError : .unknown
        do {
            try await handle.send(opcode: .projectionSessionEndedEvent, message: ProjectionSessionEndedEvent(
                identifier: identifier,
                reason: reason,
                message: error?.localizedDescription
            ))
        } catch {
            logger.warning("Failed to send ProjectionSessionEndedEvent for session \(identifier) after data channel termination: \(error)")
        }
    }

    private func handlePerformanceReport(_ report: ProjectionPerformanceReport) async {
        guard let session = await state.sessionForPerformanceReport(identifier: report.identifier) else {
            logger.warning("Received performance report for unknown session \(report.identifier)")
            return
        }

        await session.handlePerformanceReport(report)
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
            let projectionSettings = await NoctilucaServer.shared.settings.projection
            let negotiator = CodecNegotiator.create(
                from: projectionSettings.codecNegotiationPolicy,
                specifications: projectionSettings.codecSpecifications
            )

            guard var negotiatedCodec = negotiator.negotiate(with: request.preferredCodecs) else {
                logger.error("Failed to negotiate codec for projection session \(identifier)")
                try? await handle.send(opcode: .projectionSessionCreationFailedEvent, message: ProjectionSessionCreationFailedEvent(
                    identifier: identifier,
                    reason: .codecNegotiationFailed,
                    message: "No acceptable codec found"
                ))
                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: true)
                return
            }

            let desiredSize = request.preferredCodecs.first?.size?.cgSize
            guard let contentSize = await request.viewport.contentSize(codec: negotiatedCodec)?.cgSize else {
                logger.error("Content size is nil for projection request \(identifier)")
                try? await handle.send(opcode: .projectionSessionCreationFailedEvent, message: ProjectionSessionCreationFailedEvent(
                    identifier: identifier,
                    reason: .sourceNotFound,
                    message: "Failed to determine content size for the requested source"
                ))
                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: true)
                return
            }

            // 클라이언트 / 서버가 원하는 해상도 제한이 적용된 '진짜 해상도'를 반환한다
            let actualSize = if let desiredSize {
                contentSize.applySizeLimit(desiredSize)
            } else {
                contentSize
            }

            negotiatedCodec = Codec(
                fourCC: negotiatedCodec.fourCC,
                frameRate: negotiatedCodec.frameRate,
                size: SRSize(width: actualSize.width, height: actualSize.height),
                options: negotiatedCodec.options,
                quality: negotiatedCodec.quality
            )

            let openedChannel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            logger.info("Opened ProjectionDataChannel with id: \(openedChannel.identifier)")

            await openedChannel.state.setDelegate(self)

            guard await state.registerPendingDataChannel(identifier: identifier, channel: openedChannel) else {
                await openedChannel.state.setDelegate(nil)
                try? await openedChannel.handle.close()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            let projectionSession = await ProjectionSession(
                id: identifier,
                dataChannel: openedChannel,
                preferredRecorderType: projectionSettings.preferredScreenRecorder
            )
            await projectionSession.setSessionDelegate(self)
            transientSession = projectionSession

            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()

            let monitoredDisplayID = request.viewport.toScreenRecorderSource()?.monitoredDisplayID
            guard await state.activateVideoSession(identifier: identifier, session: projectionSession, displayID: monitoredDisplayID) else {
                await projectionSession.dataChannel.state.setDelegate(nil)
                await projectionSession.stop()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            try await handle.send(opcode: .projectionSessionCreatedEvent, message: ProjectionSessionCreatedEvent(
                identifier: identifier,
                source: request.viewport,
                codec: negotiatedCodec
            ))
        } catch {
            logger.error("Failed to handle projection request \(identifier): \(error)")

            try? await handle.send(opcode: .projectionSessionCreationFailedEvent, message: ProjectionSessionCreationFailedEvent(
                identifier: identifier,
                reason: .serverError,
                message: error.localizedDescription
            ))

            if let transientSession {
                await transientSession.dataChannel.state.setDelegate(nil)
                await transientSession.stop()
            }

            let targets = await state.terminateByControlMessage(identifier: identifier, kind: .video)
            await cleanupTerminationTargets(targets, closeDataChannel: true)
        }
    }

    private func handleSubscribeCursorEventsRequest(_ request: SubscribeCursorEventsRequest) async throws {
        let subscription = await CursorEventSubscription()
        await subscription.setChannel(self)

        guard await state.addCursorSubscriptionIfAbsent(subscription) else {
            subscription.destroy()
            return
        }

        await subscription.setup()

        guard await state.isCurrentCursorSubscription(subscription) else {
            subscription.destroy()
            return
        }

        try await handle.send(opcode: .subscribeCursorEventsResponse, message: SubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id
        ))
    }

    private func handleUnsubscribeCursorEventsRequest(_ request: UnsubscribeCursorEventsRequest) async throws {
        guard let subscription = await state.removeCursorSubscription() else {
            return
        }

        subscription.destroy()

        try await handle.send(opcode: .unsubscribeCursorEventsResponse, message: UnsubscribeCursorEventsResponse(
            requestID: request.requestID,
            subscriptionID: subscription.id,
            isSuccess: true
        ))
    }

    func sendCursorPositionEvent(_ state: CursorState) async throws {
        handle.send(nonblocking: .cursorEvent, message: CursorEvent(
            event: .moveEvent(CursorMoveEvent(
                displayID: state.belongsTo,
                position: SRPoint(x: state.relativePosition.x, y: state.relativePosition.y)
            ))
        ))
    }

    func sendCursorImageEvent() async throws {
        // CursorStateHolder 는 @MainActor 로 격리되어 있으므로, 모든 커서 정보를
        // 단일 MainActor hop 으로 원자적으로 읽어 경합을 방지한다.
        let payload: (data: Data, hotspot: CGPoint, size: CGSize, hash: Int)? = await MainActor.run {
            let holder = CursorStateHolder.shared
            guard let image = holder.cursorImage,
                  let hotspot = holder.cursorHotspot,
                  let png = image.pngData() else {
                return nil
            }
            return (png, hotspot, image.size, holder.cursorHash)
        }

        guard let payload else {
            return
        }

        handle.send(nonblocking: .cursorEvent, message: CursorEvent(
            event: .imageEvent(CursorImageEvent(
                cursorType: UInt64(payload.hash),
                mimeType: "image/png",
                size: SRSize(width: payload.size.width, height: payload.size.height),
                hotspot: SRPoint(x: payload.hotspot.x, y: payload.hotspot.y),
                imageData: payload.data
            ))
        ))
    }

    private func handleAudioProjectionRequest(_ request: AudioProjectionRequest) async throws {
        guard let session = clientSession else {
            return
        }

        let identifier = request.identifier
        let projectionSettings = await NoctilucaServer.shared.settings.projection

        guard projectionSettings.isAudioProjectionEnabled else {
            logger.warning("Audio projection request rejected because it is disabled in settings")
            try await handle.send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
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
            guard let negotiatedCodec = negotiateAudioCodec(
                clientPreferred: request.preferredCodecs,
                serverSpecifications: projectionSettings.audioCodecSpecifications
            ) else {
                let supportedFourCCs = projectionSettings.audioCodecSpecifications.map { $0.fourCC }
                logger.warning("No supported audio codec found for session \(identifier)")
                try await handle.send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                    identifier: identifier,
                    reason: .codecNotSupported,
                    message: "No supported audio codec found. Server supports: \(supportedFourCCs.map { $0.stringRepresentation }.joined(separator: ", "))"
                ))

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
                await cleanupTerminationTargets(targets, closeDataChannel: true)
                return
            }

            logger.info("Negotiated audio codec: \(negotiatedCodec.fourCC.stringRepresentation) for session \(identifier)")

            let openedChannel = try await session.channelManager.openChannel(for: .projectionData, identifier: identifier) as! ProjectionDataChannel
            logger.info("Opened ProjectionDataChannel for audio with id: \(openedChannel.identifier)")

            await openedChannel.state.setDelegate(self)

            guard await state.registerPendingDataChannel(identifier: identifier, channel: openedChannel) else {
                await openedChannel.state.setDelegate(nil)
                try? await openedChannel.handle.close()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            let projectionSession = await AudioProjectionSession(
                id: identifier,
                dataChannel: openedChannel
            )
            transientSession = projectionSession

            try await projectionSession.prepare(request, codec: negotiatedCodec)
            try await projectionSession.start()

            guard await state.activateAudioSession(identifier: identifier, session: projectionSession) else {
                await projectionSession.dataChannel.state.setDelegate(nil)
                await projectionSession.stop()

                let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
                await cleanupTerminationTargets(targets, closeDataChannel: false)
                return
            }

            try await handle.send(opcode: .audioSessionCreatedEvent, message: AudioSessionCreatedEvent(
                identifier: identifier,
                source: request.source,
                codec: negotiatedCodec
            ))
        } catch {
            logger.error("Failed to handle audio projection request \(identifier): \(error)")

            try? await handle.send(opcode: .audioSessionCreationFailedEvent, message: AudioSessionCreationFailedEvent(
                identifier: identifier,
                reason: .unknown,
                message: error.localizedDescription
            ))

            if let transientSession {
                await transientSession.dataChannel.state.setDelegate(nil)
                await transientSession.stop()
            }

            let targets = await state.terminateByControlMessage(identifier: identifier, kind: .audio)
            await cleanupTerminationTargets(targets, closeDataChannel: true)
        }
    }

    /// 클라이언트 선호 코덱 목록에서 서버가 지원하는 첫 번째 코덱을 선택하고,
    /// 서버 설정의 비트레이트를 적용한 AudioCodec을 반환
    private func negotiateAudioCodec(clientPreferred: [SiriusKit.AudioCodec], serverSpecifications: [AudioCodecSpecification]) -> SiriusKit.AudioCodec? {
        let serverFourCCs = serverSpecifications.map { $0.fourCC }

        for clientCodec in clientPreferred {
            guard serverFourCCs.contains(clientCodec.fourCC) else { continue }
            guard let spec = serverSpecifications.first(where: { $0.fourCC == clientCodec.fourCC }) else { continue }

            return AudioCodec(
                fourCC: clientCodec.fourCC,
                quality: .constantBitrate(bitrateKbps: UInt32(spec.bitrateKbps)),
                sampleRate: clientCodec.sampleRate,
                channelCount: clientCodec.channelCount,
                options: clientCodec.options
            )
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

extension ProjectionChannel: ProjectionSessionDelegate {
    func projectionSession(_ session: ProjectionSession, didChangeResolution newCodec: Codec) {
        let sessionID = session.id
        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.handle.send(opcode: .projectionSessionChangedEvent, message: ProjectionSessionChangedEvent(
                    identifier: sessionID,
                    reason: 1 /* resolutionChanged */,
                    source: nil,
                    codec: newCodec
                ))
            } catch {
                self.logger.warning("Failed to send ProjectionSessionChangedEvent for session \(sessionID): \(error)")
            }
        }
    }

    func projectionSession(_ session: ProjectionSession, didFailWithError error: Error) {
        let sessionID = session.id
        Task { [weak self] in
            guard let self else { return }

            self.logger.error("ProjectionSession \(sessionID) failed: \(error)")

            let targets = await self.state.terminateByControlMessage(identifier: sessionID, kind: .video)
            await self.cleanupTerminationTargets(targets, closeDataChannel: true)

            do {
                try await self.handle.send(opcode: .projectionSessionEndedEvent, message: ProjectionSessionEndedEvent(
                    identifier: sessionID,
                    reason: VideoSessionEndReason.internalError,
                    message: error.localizedDescription
                ))
            } catch {
                self.logger.warning("Failed to send ProjectionSessionEndedEvent for session \(sessionID): \(error)")
            }
        }
    }
}

fileprivate extension ProjectionSource {
    @MainActor
    func contentSize(codec: Codec) -> SRSize? {
        switch value {
        case .entireDisplay(let source):
            let layoutManager = DisplayLayoutManager.shared
            let displayID: CGDirectDisplayID? = switch (source.displayID) {
            case -1:
                layoutManager.displayLayouts.keys.first { CGDisplayIsMain($0) != 0 }!
            case -2:
                nil // entire display layout is not supported yet
            default:
                CGDirectDisplayID(source.displayID)
            }

            if let displayID, let display = DisplayLayoutManager.shared.displayLayouts[displayID] {
                switch codec.option(.displayDensity) {
                case .kDisplayDensityBest:
                    return SRSize(width: display.displayResolution.width, height: display.displayResolution.height)
                default:
                    return SRSize(width: display.frame.size.width, height: display.frame.size.height)
                }
            } else {
                return nil
            }

        case .region(let region):
            return SRSize(width: region.region.width, height: region.region.height)

        case .singleWindow(let window):
            let contextManager = DesktopContextManager.shared
            // FIXME: window가 속한 display를 끌어다가 scale factor를 곱해야 한다
            guard let windowInfo = contextManager.globalWindowList().first(where: { $0.windowID == window.windowID! }) else {
                return nil
            }

            let size = SRSize(width: windowInfo.bounds.width, height: windowInfo.bounds.height)
            return size

        default:
            return nil
        }
    }
}
