//
//  ProjectionSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

import SiriusKit

extension AppSettings {
    struct Projection: Category {
        /// 0.9.10 에서 reference 구현이 제거된 타일링 이미지 코덱 fourCC 목록.
        /// wire identifier 자체는 SiriusKit 차원에서 reserved 로 보존되므로
        /// 디코딩은 성공하지만, 더 이상 negotiable 하지 않으므로 settings 로딩 시점에
        /// silently 필터링한다.
        private static let deprecatedTilingFourCCs: Set<UInt32> = [
            CodecFourCC.zrle.rawValue,
            CodecFourCC.mjpg.rawValue,
            CodecFourCC.webp.rawValue,
        ]

        static func defaultCodecSpecifications() -> [CodecSpecification] {
            if SystemCapability.isVirtualMachine {
                return [.vp8]
            }

            return [.hevc, .h264, .vp8]
        }
        
        /// 사용자가 선호하는 화면 녹화기 구현체 순서.
        /// 잠금 화면 등에서는 AVFoundation 기반 녹화기로 폴백할 수 있습니다.
        var preferredScreenRecorder: ScreenRecorderType = .screenCaptureKit
        
        var allowModifyDisplayLayout: Bool = true
        var allowVirtualDisplay: Bool = true
        
        /// 코덱 협상 정책.
        var codecNegotiationPolicy: CodecNegotiationPolicy = .balanced
        
        var codecSpecifications: [CodecSpecification] = Self.defaultCodecSpecifications()
        
        /// 오디오 프로젝션 활성화 여부
        var isAudioProjectionEnabled: Bool = true
        
        /// 오디오 코덱 우선순위
        var audioCodecSpecifications: [AudioCodecSpecification] = [.opus, .pcmu, .pcma]

        init() {}

        enum CodingKeys: String, CodingKey {
            case preferredScreenRecorder
            case allowModifyDisplayLayout
            case allowVirtualDisplay
            case codecNegotiationPolicy
            case codecSpecifications
            case isAudioProjectionEnabled
            case audioCodecSpecifications
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            preferredScreenRecorder = container.decodeSafe(ScreenRecorderType.self, forKey: .preferredScreenRecorder, default: preferredScreenRecorder)
            
            allowModifyDisplayLayout = container.decodeSafe(Bool.self, forKey: .allowModifyDisplayLayout, default: allowModifyDisplayLayout)
            allowVirtualDisplay = container.decodeSafe(Bool.self, forKey: .allowVirtualDisplay, default: allowVirtualDisplay)

            codecNegotiationPolicy = container.decodeSafe(CodecNegotiationPolicy.self, forKey: .codecNegotiationPolicy, default: codecNegotiationPolicy)
            codecSpecifications = container.decodeSafe([CodecSpecification].self, forKey: .codecSpecifications, default: codecSpecifications)

            // 0.9.10 — 이전 버전 settings.json 에 deprecated 타일링 코덱이 포함된 경우 silently 필터링.
            let originalCount = codecSpecifications.count
            codecSpecifications.removeAll { Self.deprecatedTilingFourCCs.contains($0.fourCC.rawValue) }
            if codecSpecifications.count != originalCount {
                /*
                NoctilucaLogger(category: "AppSettings").info(
                    "Filtered \(originalCount - codecSpecifications.count) deprecated tiling codec(s) from settings.json (zrle/mjpg/webp removed in 0.9.10)"
                )
                 */
                if codecSpecifications.isEmpty {
                    codecSpecifications = Self.defaultCodecSpecifications()
                }
            }

            isAudioProjectionEnabled = container.decodeSafe(Bool.self, forKey: .isAudioProjectionEnabled, default: isAudioProjectionEnabled)
            audioCodecSpecifications = container.decodeSafe([AudioCodecSpecification].self, forKey: .audioCodecSpecifications, default: audioCodecSpecifications)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(preferredScreenRecorder, forKey: .preferredScreenRecorder)
            try container.encode(allowModifyDisplayLayout, forKey: .allowModifyDisplayLayout)
            try container.encode(allowVirtualDisplay, forKey: .allowVirtualDisplay)
            try container.encode(codecNegotiationPolicy, forKey: .codecNegotiationPolicy)
            try container.encode(codecSpecifications, forKey: .codecSpecifications)
            try container.encode(isAudioProjectionEnabled, forKey: .isAudioProjectionEnabled)
            try container.encode(audioCodecSpecifications, forKey: .audioCodecSpecifications)
        }
    }
}
