//
//  GeneralSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    /// 지터 버퍼 프리셋 종류.
    enum JitterBufferPreset: String, Codable, CaseIterable {
        case legacy
        case lowLatency
        case lowLatencyPlus
        case ultraLowLatency

        var displayName: String {
            switch self {
            case .legacy: return "안정성 우선"
            case .lowLatency: return "저지연"
            case .lowLatencyPlus: return "저지연+"
            case .ultraLowLatency: return "초저지연"
            }
        }

        var description: String {
            switch self {
            case .legacy:
                return "버퍼를 넉넉하게 잡아 네트워크 지터에 강한 안정적인 재생을 합니다.\n딜레이가 다소 있을 수 있습니다."
            case .lowLatency:
                return "안정성과 지연 시간의 균형을 맞춘 기본 프리셋입니다."
            case .lowLatencyPlus:
                return "저지연 프리셋보다 더 적극적으로 지연 시간을 줄입니다.\n네트워크 상태가 불안정하면 끊김이 발생할 수 있습니다."
            case .ultraLowLatency:
                return "지연 시간 최소화를 최우선으로 합니다.\n네트워크 상태가 좋지 않으면 끊김이나 프레임 드롭이 빈번해질 수 있습니다."
            }
        }

        var bufferPreset: VideoJitterBuffer.Preset {
            switch self {
            case .legacy: return .legacy
            case .lowLatency: return .lowLatency
            case .lowLatencyPlus: return .lowLatencyPlus
            case .ultraLowLatency: return .ultraLowLatency
            }
        }
    }

    struct Projection: Category {
        var enableJitterBuffer: Bool = true
        var jitterBufferPreset: JitterBufferPreset = .lowLatency

        init() {}

        enum CodingKeys: String, CodingKey {
            case enableJitterBuffer
            case jitterBufferPreset
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            enableJitterBuffer = container.decodeSafe(Bool.self, forKey: .enableJitterBuffer, default: true)
            jitterBufferPreset = container.decodeSafe(JitterBufferPreset.self, forKey: .jitterBufferPreset, default: .lowLatency)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enableJitterBuffer, forKey: .enableJitterBuffer)
            try container.encode(jitterBufferPreset, forKey: .jitterBufferPreset)
        }
    }
}
