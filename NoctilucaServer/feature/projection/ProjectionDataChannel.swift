//
//  ProjectionChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit

import CoreMedia

class ProjectionDataChannel: Channel {
    var isFrameDescriptionSent: Bool = false
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        // 서버 사이드 구현이므로 별도 처리를 하지 않는다 (= 클라이언트로 보내기만 하는 역할.)
    }
    
    func send(videoFrame frame: EncodedFrame) async throws {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data
        
        if !isFrameDescriptionSent {
            if let formatDescription = frame.formatDescription {
                var data = Data()
                let parameterCount = UInt32(formatDescription.parameterSets.count).bigEndian
                
                withUnsafeBytes(of: parameterCount) { ptr in
                    data.append(ptr.bindMemory(to: UInt32.self))
                }
                
                for parameter in formatDescription.parameterSets {
                    let size = UInt32(parameter.count).bigEndian
                    
                    withUnsafeBytes(of: size) { ptr in
                        data.append(ptr.bindMemory(to: UInt32.self))
                    }
                    
                    data.append(parameter)
                }
                
                try await self.send(frame: SiriusFrame(opcode: .streamDescription,
                                                       length: UInt32(data.count),
                                                       data: consume data))
                
                isFrameDescriptionSent = true
            }
        }
        
        
        
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
}
