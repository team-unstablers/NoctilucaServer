//
//  ProjectionDataChannel.swift
//  MockServer
//
//  Copied from NoctilucaServer/feature/projection/ProjectionDataChannel.swift
//

import SiriusKit
import CoreMedia

protocol ProjectionDataChannelDelegate: AnyObject {
    func projectionDataChannelDidClose(_ channel: ProjectionDataChannel)
    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error)
}

class ProjectionDataChannel: Channel {
    weak var projectionDelegate: ProjectionDataChannelDelegate?

    override var serviceClass: ServiceClass { .realtimeVideo }

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        // Server-side: send only
    }

    override func handleStreamClose() {
        super.handleStreamClose()
        projectionDelegate?.projectionDataChannelDidClose(self)
    }

    override func handleStreamError(error: any Error) {
        super.handleStreamError(error: error)
        projectionDelegate?.projectionDataChannel(self, didEncounterError: error)
    }

    func send(parameterSetMessage: CodecParameterSetMessage) {
        self.sendNonBlocking(opcode: .codecParameterSets, message: parameterSetMessage)
    }

    func send(degradationNotice: DegradationNotice) {
        self.sendNonBlocking(opcode: .degradationNotice, message: degradationNotice)
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

        self.sendNonBlocking(frame: consume siriusFrame)
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

        self.sendNonBlocking(frame: consume siriusFrame)
    }
}
