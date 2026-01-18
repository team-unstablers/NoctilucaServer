//
//  ProjectionSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct Projection: Category {
        /// 사용자가 선호하는 화면 녹화기 구현체 순서.
        /// 잠금 화면 등에서는 AVFoundation 기반 녹화기로 폴백할 수 있습니다.
        var preferredScreenRecorder: ScreenRecorderType = .screenCaptureKit
        
        /// 코덱 협상 정책.
        var codecNegotiationPolicy: CodecNegotiationPolicy = .balanced
        
        var codecSpecifications: [CodecSpecification] = [
            .hevc,
            .h264
        ]

        init() {}

        enum CodingKeys: String, CodingKey {
            case preferredScreenRecorder
            case codecNegotiationPolicy
            case codecSpecifications
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            preferredScreenRecorder = container.decodeSafe(ScreenRecorderType.self, forKey: .preferredScreenRecorder, default: preferredScreenRecorder)
            codecNegotiationPolicy = container.decodeSafe(CodecNegotiationPolicy.self, forKey: .codecNegotiationPolicy, default: codecNegotiationPolicy)
            codecSpecifications = container.decodeSafe([CodecSpecification].self, forKey: .codecSpecifications, default: codecSpecifications)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(preferredScreenRecorder, forKey: .preferredScreenRecorder)
            try container.encode(codecNegotiationPolicy, forKey: .codecNegotiationPolicy)
            try container.encode(codecSpecifications, forKey: .codecSpecifications)
        }
    }
}
