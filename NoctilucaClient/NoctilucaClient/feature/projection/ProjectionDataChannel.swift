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
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput)
}

class ProjectionDataChannel: Channel {
    private let logger = SiriusLogger(category: "ProjectionDataChannel", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    
    var formatDescription: CMFormatDescription?
    
    weak var delegate: ProjectionDataChannelDelegate?
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        if frame.opcode == .streamDescription {
            let data = frame.data
            let count = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            var parameters: [Data] = []
            
            var offset = 4
            
            for i in 0..<count {
                let size = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                
                let parameterData = data.subdata(in: (offset + 4)..<(offset + 4 + Int(size)))
                parameters.append(parameterData)
                
                offset += (4 + Int(size))
            }
            
            self.formatDescription = try CMFormatDescription(h264ParameterSets: parameters)
            return
        }
        
        guard frame.opcode == .frameData else {
            return
        }
        
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
            formatDescription: formatDescription
        )
        
        delegate?.projectionDataChannel(self, didReceiveFrame: consume frameInput)
    }
}
