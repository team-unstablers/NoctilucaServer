//
//  CodecOptionValue+QuantizeLevel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/28/26.
//

public extension CodecOptionValue {
    /// 양자화 없음 (원본 유지)
    static let kQuantizeLevelNone = Self(rawValue: "0")

    /// 양자화 레벨 1 (가벼운 양자화)
    static let kQuantizeLevel1 = Self(rawValue: "1")

    /// 양자화 레벨 2 (중간 양자화, 기본값)
    static let kQuantizeLevel2 = Self(rawValue: "2")

    /// 양자화 레벨 3 (강한 양자화)
    static let kQuantizeLevel3 = Self(rawValue: "3")

    /// 양자화 레벨 4 (매우 강한 양자화)
    static let kQuantizeLevel4 = Self(rawValue: "4")

    /// 양자화 레벨 5 (최대 양자화)
    static let kQuantizeLevel5 = Self(rawValue: "5")
}
