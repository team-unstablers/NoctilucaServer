//
//  CodecOptionValue+ColorFormat.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

public extension CodecOptionValue {
    /// 자동 픽셀 포맷 선택. 현 시점에서는 yuv420으로 폴백한다.
    static let kColorFormatAuto = Self(rawValue: "auto")

    // YUV 4:2:0 픽셀 포맷
    static let kColorFormatYUV420 = Self(rawValue: "yuv420")
    
    // YUV 4:4:4 픽셀 포맷
    static let kColorFormatYUV444 = Self(rawValue: "yuv444")
}
