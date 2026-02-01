//
//  AudioCodecSpecification+SiriusKit.swift
//  NoctilucaClient
//
//  Created by Codex on 1/30/26.
//

import Foundation
import SiriusKitClient

extension AudioCodecSpecification {
    func toSiriusKitCodec() -> SiriusKitClient.AudioCodec {
        return SiriusKitClient.AudioCodec(
            fourCC: self.fourCC,
            quality: .auto, // 기본 품질 자동
            options: CodecOptions(
                mandatory: [:],
                optional: self.options
            )
        )
    }
}
