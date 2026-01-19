//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Combine

import CoreGraphics

import SiriusKitClient

class ProjectionChannel: Channel, ObservableObject {
    private let logger = SiriusLogger(category: "ProjectionChannel", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    private static let defaultSpecifications: [CodecSpecification] = [.hevc, .h264]
    
    private(set) var pendingSessions: [UUID: (ProjectionSessionCreatedEvent) -> Void] = [:]
    private(set) var sessions: [UUID: ProjectionSession] = [:]
    
    @Published
    private(set) var cursorImage: CGImage? = nil

    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
        
        assert(direction == .local, "ProjectionChannel must be opened from client side")
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        switch frame.opcode {
        case .projectionSessionCreatedEvent:
            let event = try ProjectionSessionCreatedEvent.fromProtobufBytes(frame.data)
            self.logger.info("Received ProjectionSessionCreatedEvent: sessionId=\(event.identifier)")
            
            if let continuation = self.pendingSessions[event.identifier] {
                continuation(event)
            } else {
                self.logger.warning("No pending session found for identifier: \(event.identifier)")
            }
            
        case .cursorEvent:
            let event = try CursorEvent.fromProtobufBytes(frame.data)
            try await self.handleCursorEvent(event)
        default:
            break
        }
    }
    
    func createSession(projectionSettings: SessionSettings.Projection?) async throws -> ProjectionSession {
        guard let clientSession = self.clientSession else {
            fatalError()
        }
        
        let identifier = UUID()

        let preferredCodecs = buildPreferredCodecs(from: projectionSettings)
        try await sendProjectionRequest(identifier: identifier, preferredCodecs: preferredCodecs)
        
        let createdEvent = await withCheckedContinuation { cont in
            self.pendingSessions[identifier] = { event in
                self.pendingSessions.removeValue(forKey: identifier)
                cont.resume(returning: event)
            }
        }
        
        let channel = clientSession.channelManager.channels[identifier] as! ProjectionDataChannel
        
        let session = ProjectionSession(id: identifier, dataChannel: channel, controlChannel: self)
        
        try await session.prepare(codec: createdEvent.codec)
        try await session.start()
        
        self.sessions[identifier] = session
        return session
    }

    private func sendProjectionRequest(identifier: UUID, preferredCodecs: [Codec]) async throws {
        try await self.send(opcode: .projectionRequest, message: ProjectionRequest(
            identifier: identifier,
            viewport: ProjectionSource(
                value: .entireDisplay(EntireDisplayProjectionSource(displayID: Int32(-1))),
                flags: .none
            ),
            preferredCodecs: preferredCodecs
        ))
    }

    private func buildPreferredCodecs(from projectionSettings: SessionSettings.Projection?) -> [Codec] {
        guard let projectionSettings else {
            return Self.defaultSpecifications.map { $0.toSiriusKitCodec() }
        }

        switch projectionSettings.codecSettingsMode {
        case .useDefault:
            return Self.defaultSpecifications.map { $0.toSiriusKitCodec() }
        case .manual:
            let specifications = projectionSettings.codecSpecifications
            guard !specifications.isEmpty else {
                logger.warning("Projection codec specifications are empty; sending empty preferredCodecs.")
                return []
            }

            let codecs = specifications.map { $0.toSiriusKitCodec() }
            return applyNegotiationPolicy(projectionSettings.codecNegotiationPolicy, to: codecs)
        }
    }

    private func applyNegotiationPolicy(_ policy: SessionSettings.CodecNegotiationPolicy, to codecs: [Codec]) -> [Codec] {
        let shouldForceMandatory = policy == .asMandatory

        return codecs.map { codec in
            let options = remapOptions(codec.options, mandatory: shouldForceMandatory)
            return Codec(
                fourCC: codec.fourCC,
                frameRate: codec.frameRate,
                size: codec.size,
                options: options,
                quality: codec.quality
            )
        }
    }

    private func remapOptions(_ options: CodecOptions, mandatory: Bool) -> CodecOptions {
        var combined = options.mandatory
        combined.merge(options.optional, uniquingKeysWith: { _, new in new })

        if mandatory {
            return CodecOptions(mandatory: combined, optional: [:])
        }

        return CodecOptions(mandatory: [:], optional: combined)
    }
    
    func subscribeCursorEvents() async throws {
        try await self.send(opcode: .subscribeCursorEventsRequest, message: SubscribeCursorEventsRequest(
            // FIXME
            requestID: 0,
            flags: 0
        ))
    }
    
    func unsubscribeCursorEvents() async throws {
        try await self.send(opcode: .unsubscribeCursorEventsRequest, message: UnsubscribeCursorEventsRequest(
            // FIXME
            requestID: 0,
            subscriptionID: UUID()
        ))
    }
    
    private func handleCursorEvent(_ event: CursorEvent) async throws {
        self.logger.info("Received cursorEvent: cursorType=\(event.cursorType)")
        
        guard let dataProvider = CGDataProvider(data: event.imageData as CFData) else {
            return
        }
        
        let cursorImage = CGImage(
            pngDataProviderSource: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
        
        await MainActor.run {
            self.cursorImage = cursorImage
        }
    }

}
