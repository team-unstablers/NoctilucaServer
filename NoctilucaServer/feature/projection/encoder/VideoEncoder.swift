//
//  VideoEncoder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import AVFoundation

enum VideoEncoderCodec {
    case h264
    case hevc
}

struct VideoEncoderArgs {
    let codec: VideoEncoderCodec
}

protocol VideoEncoder {
    func prepare(args: VideoEncoderArgs) throws
    
    func encode(sampleBuffer: CMSampleBuffer)
}
