//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation

import CoreMedia

import SiriusKitClient

protocol ProjectionDataChannelDelegate: AnyObject {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveCodecParameterSets codecParameterSets: consuming CodecParameterSetMessage)
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput)
}

class ProjectionDataChannel: Channel {
    private let logger = SiriusLogger(category: "ProjectionDataChannel", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    
    weak var delegate: ProjectionDataChannelDelegate?
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        switch frame.opcode {
        case .codecParameterSets:
            try await handleCodecParameterSets(frame)
        case .frameData:
            try await handleFrameData(frame)
        default:
            break
        }
    }
    
    func handleCodecParameterSets(_ frame: SiriusFrame) async throws {
        let codecParameterSetMessage = try CodecParameterSetMessage.fromProtobufBytes(frame.data)
        
        delegate?.projectionDataChannel(self, didReceiveCodecParameterSets: consume codecParameterSetMessage)
    }
    
    func handleFrameData(_ frame: SiriusFrame) async throws {
        // <header length: uint32> <frame data length: uint32> <header bytes> <frame data bytes>
        let data = frame.data
        
        var headerLength = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        var frameDataLength = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        guard data.count == (8 + headerLength + frameDataLength) else {
            logger.error("Invalid frame data length: expected \(8 + headerLength + frameDataLength), got \(data.count)")
            throw ChannelError.invalidFrame
        }
        
        let rawHeader = data.subdata(in: 8..<(8 + Int(headerLength)))
        
        let header = try FrameDataHeader.fromProtobufBytes(rawHeader)
        let frameData = data.subdata(in: (8 + Int(headerLength))..<(8 + Int(headerLength) + Int(frameDataLength)))
        
        let frameInput = EncodedFrameInput(
            header: consume header,
            data: consume frameData,
            formatDescription: nil
        )
        
        delegate?.projectionDataChannel(self, didReceiveFrame: consume frameInput)
    }
}
