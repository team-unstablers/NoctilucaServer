//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit

import CoreMedia

protocol ProjectionDataChannelDelegate: AnyObject {
    func projectionDataChannelDidClose(_ channel: ProjectionDataChannel)
    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error)
}

class ProjectionDataChannel: Channel {
    weak var projectionDelegate: ProjectionDataChannelDelegate?

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        // 서버 사이드 구현이므로 별도 처리를 하지 않는다 (= 클라이언트로 보내기만 하는 역할.)
    }

    override func handleStreamClose() {
        super.handleStreamClose()
        projectionDelegate?.projectionDataChannelDidClose(self)
    }

    override func handleStreamError(error: any Error) {
        super.handleStreamError(error: error)
        projectionDelegate?.projectionDataChannel(self, didEncounterError: error)
    }
    
    func send(parameterSetMessage: CodecParameterSetMessage) async throws {
        try await self.send(opcode: .codecParameterSets, message: parameterSetMessage)
    }

    func send(degradationNotice: DegradationNotice) async throws {
        try await self.send(opcode: .degradationNotice, message: degradationNotice)
    }
    
    func send(videoFrame frame: EncodedFrame) async throws {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data
        
        // header.count /  / frameData.count / header / frameData
        let siriusFrameSize = ((4 + 4) + serializedHeader.count + frameData.count)
        var siriusFrameData = Data(count: siriusFrameSize)
        
        // perform memcpy
        // 1. header size
        let headerSize = UInt32(serializedHeader.count).bigEndian
        withUnsafeBytes(of: headerSize) { ptr in
            siriusFrameData.replaceSubrange(0..<4, with: ptr)
        }
        
        // 2. frame data size
        let frameDataSize = UInt32(frameData.count).bigEndian
        withUnsafeBytes(of: frameDataSize) { ptr in
            siriusFrameData.replaceSubrange(4..<8, with: ptr)
        }
        
        // 3. header bytes
        // FIXME: 얘네 좀 더 빠른 방법 없음?
        let range = 8..<(8 + serializedHeader.count)
        siriusFrameData.replaceSubrange(range, with: serializedHeader)
        
        // 4. frame data bytes
        // FIXME: 얘네 좀 더 빠른 방법 없음?
        let frameDataRange = (8 + serializedHeader.count)..<siriusFrameSize
        siriusFrameData.replaceSubrange(frameDataRange, with: frameData)
        
        let siriusFrame = SiriusFrame(
            opcode: .frameData,
            length: UInt32(siriusFrameSize),
            data: consume siriusFrameData
        )
        
        try await self.send(frame: consume siriusFrame)
    }

    func send(audioFrame frame: EncodedAudioFrame) async throws {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data

        // header.count / frameData.count / header / frameData
        let siriusFrameSize = ((4 + 4) + serializedHeader.count + frameData.count)
        var siriusFrameData = Data(count: siriusFrameSize)

        // perform memcpy
        // 1. header size
        let headerSize = UInt32(serializedHeader.count).bigEndian
        withUnsafeBytes(of: headerSize) { ptr in
            siriusFrameData.replaceSubrange(0..<4, with: ptr)
        }

        // 2. frame data size
        let frameDataSize = UInt32(frameData.count).bigEndian
        withUnsafeBytes(of: frameDataSize) { ptr in
            siriusFrameData.replaceSubrange(4..<8, with: ptr)
        }

        // 3. header bytes
        let range = 8..<(8 + serializedHeader.count)
        siriusFrameData.replaceSubrange(range, with: serializedHeader)

        // 4. frame data bytes
        let frameDataRange = (8 + serializedHeader.count)..<siriusFrameSize
        siriusFrameData.replaceSubrange(frameDataRange, with: frameData)

        let siriusFrame = SiriusFrame(
            opcode: .frameData,
            length: UInt32(siriusFrameSize),
            data: consume siriusFrameData
        )

        try await self.send(frame: consume siriusFrame)
    }
}
