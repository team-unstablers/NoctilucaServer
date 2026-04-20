//
//  ProjectionDataChannel.swift
//  MockServer
//
//  Copied from NoctilucaServer/feature/projection/ProjectionDataChannel.swift
//

import SiriusKit
import CoreMedia

protocol ProjectionDataChannelDelegate: AnyObject, Sendable {
    func projectionDataChannelDidClose(_ channel: ProjectionDataChannel)
    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error)
}

// MARK: - ProjectionDataChannelState

actor ProjectionDataChannelState {
    private weak var delegate: ProjectionDataChannelDelegate?

    func setDelegate(_ delegate: ProjectionDataChannelDelegate?) {
        self.delegate = delegate
    }

    func getDelegate() -> ProjectionDataChannelDelegate? {
        return self.delegate
    }
}

// MARK: - ProjectionDataChannel

final class ProjectionDataChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .realtimeVideo

    private let logger = SiriusLogger(category: "ProjectionDataChannel", subsystem: "app.noctiluca.mockserver")

    let state = ProjectionDataChannelState()

    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionDataChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        // Server-side: send only
    }

    func handleError(error: any Error) async {
        let delegate = await state.getDelegate()
        delegate?.projectionDataChannel(self, didEncounterError: error)
    }

    func handleStreamClose() async {
        let delegate = await state.getDelegate()
        delegate?.projectionDataChannelDidClose(self)
    }

    // MARK: - Send helpers

    func send(parameterSetMessage: CodecParameterSetMessage) {
        handle.send(nonblocking: .codecParameterSets, message: parameterSetMessage)
    }

    func send(degradationNotice: DegradationNotice) {
        handle.send(nonblocking: .degradationNotice, message: degradationNotice)
    }

    func send(videoFrame frame: EncodedFrame) {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data

        let siriusFrameSize = ((4 + 4) + serializedHeader.count + frameData.count)
        var siriusFrameData = Data(count: siriusFrameSize)

        let headerSize = UInt32(serializedHeader.count).bigEndian
        withUnsafeBytes(of: headerSize) { ptr in
            siriusFrameData.replaceSubrange(0..<4, with: ptr)
        }

        let frameDataSize = UInt32(frameData.count).bigEndian
        withUnsafeBytes(of: frameDataSize) { ptr in
            siriusFrameData.replaceSubrange(4..<8, with: ptr)
        }

        let range = 8..<(8 + serializedHeader.count)
        siriusFrameData.replaceSubrange(range, with: serializedHeader)

        let frameDataRange = (8 + serializedHeader.count)..<siriusFrameSize
        siriusFrameData.replaceSubrange(frameDataRange, with: frameData)

        let siriusFrame = SiriusFrame(
            opcode: .frameData,
            length: UInt32(siriusFrameSize),
            data: consume siriusFrameData
        )

        handle.send(nonblocking: consume siriusFrame)
    }

    func send(audioFrame frame: EncodedAudioFrame) {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data

        let siriusFrameSize = ((4 + 4) + serializedHeader.count + frameData.count)
        var siriusFrameData = Data(count: siriusFrameSize)

        let headerSize = UInt32(serializedHeader.count).bigEndian
        withUnsafeBytes(of: headerSize) { ptr in
            siriusFrameData.replaceSubrange(0..<4, with: ptr)
        }

        let frameDataSize = UInt32(frameData.count).bigEndian
        withUnsafeBytes(of: frameDataSize) { ptr in
            siriusFrameData.replaceSubrange(4..<8, with: ptr)
        }

        let range = 8..<(8 + serializedHeader.count)
        siriusFrameData.replaceSubrange(range, with: serializedHeader)

        let frameDataRange = (8 + serializedHeader.count)..<siriusFrameSize
        siriusFrameData.replaceSubrange(frameDataRange, with: frameData)

        let siriusFrame = SiriusFrame(
            opcode: .frameData,
            length: UInt32(siriusFrameSize),
            data: consume siriusFrameData
        )

        handle.send(nonblocking: consume siriusFrame)
    }
}
