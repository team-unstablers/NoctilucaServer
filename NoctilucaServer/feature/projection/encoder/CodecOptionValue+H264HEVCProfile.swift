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
    
    /// H.264 / HEVC High Profile
    static let kProfileHigh = Self(rawValue: "high")
    
    /// H.264 / HEVC Main Profile
    static let kProfileMain = Self(rawValue: "main")
    
    /// H.264 / HEVC Baseline Profile
    static let kProfileBaseline = Self(rawValue: "baseline")
}
