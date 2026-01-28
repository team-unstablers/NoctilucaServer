//
//  ScreenRecorderType.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

enum ScreenRecorderType: String, Codable, Hashable, Equatable {
    case avFoundation = "avfoundation"
    case screenCaptureKit = "screencapturekit"
#if DEBUG
    case null = "null"
#endif

    init(from decoder: any Decoder) throws {
        let container = try? decoder.singleValueContainer()
        let rawValue = (try? container?.decode(String.self)) ?? Self.screenCaptureKit.rawValue
        self = ScreenRecorderType(rawValue: rawValue) ?? .screenCaptureKit
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    static var allCases: [ScreenRecorderType] {
#if DEBUG
        return [.screenCaptureKit, .avFoundation, .null]
#else
        return [.screenCaptureKit, .avFoundation]
#endif
    }
    
    var displayName: String {
        switch self {
        case .avFoundation:
            return String(
                localized: "projection.recorder.type.avfoundation.display_name",
                defaultValue: "AVFoundation 레코더"
            )
        case .screenCaptureKit:
            return String(
                localized: "projection.recorder.type.screencapturekit.display_name",
                defaultValue: "ScreenCaptureKit 레코더"
            )
#if DEBUG
        case .null:
            return String(
                localized: "projection.recorder.type.null.display_name",
                defaultValue: "NULL Recorder"
            )
#endif
        }
    }
    
    var description: String {
        switch self {
        case .avFoundation:
            return String(
                localized: "projection.recorder.type.avfoundation.description",
                defaultValue: "AVFoundation 프레임워크를 사용한 기본 화면 레코더입니다. 성능은 좋지 않지만, 호환성이 높습니다."
            )
        case .screenCaptureKit:
            return String(
                localized: "projection.recorder.type.screencapturekit.description",
                defaultValue: "macOS 12.3부터 사용 가능한 고성능 화면 레코더입니다.\n잠금 화면 등의 특수한 상황에서는 AVFoundation 레코더로 자동 폴백됩니다."
            )
#if DEBUG
        case .null:
            return String(
                localized: "projection.recorder.type.null.description",
                defaultValue: "화면 녹화를 수행하지 않고 검은 화면만을 전송하는 더미 레코더입니다. 개발 용도로만 사용하세요."
            )
#endif
        }
    }
    
}
