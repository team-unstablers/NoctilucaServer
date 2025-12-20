//
//  CodecOption.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

extension CodecOptionValue {
    /// 자동 프로파일 선택
    static let kProfileAuto = Self(rawValue: "auto")
    
    /// H.264 High Profile
    static let kProfileH264High = Self(rawValue: "h264_high")
    
    /// H.264 Main Profile
    static let kProfileH264Main = Self(rawValue: "h264_main")
    
    /// H.264 Baseline Profile
    static let kProfileH264Baseline = Self(rawValue: "h264_baseline")
    
    /// HEVC Main Profile
    static let kProfileHEVCMain = Self(rawValue: "hevc_main")
    
    /// HEVC Main10 Profile
    static let kProfileHEVCMain10 = Self(rawValue: "hevc_main10")
}
