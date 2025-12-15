//
//  CodecParameterType.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/15/25.
//

import Foundation

public struct ProjectionDataFlags: OptionSet, Hashable, Equatable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let none = ProjectionDataFlags([])
    public static let isKeyframe = ProjectionDataFlags(rawValue: 0b0000_0001)
    
    /// H.264 / HEVC: 이 프레임은 Annex-B 형식의 NALU를 포함합니다.
    ///
    /// - SiriusKit은 기본적으로 AVCC 형식을 사용하지만, 이 플래그를 통해 Annex-B 형식도 지원할 수 있습니다.
    /// - Annex-B 형식을 사용하는 경우 CodecParameterSetMessage(opcode `0x8002`) 의 전송은 하지 않아도 됩니다. (Annex-B에서는 SPS/PPS/VPS가 NALU 스트림 내에 포함될 수 있기 때문입니다.)
    public static let H264_HEVC_isAnnexBFormatted = ProjectionDataFlags(rawValue: 0b0001_0000_0000)
}
