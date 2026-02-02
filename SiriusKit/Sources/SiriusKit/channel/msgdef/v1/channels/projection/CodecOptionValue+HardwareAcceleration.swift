//
//  CodecOptionValue+ColorFormat.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

public extension CodecOptionValue {
    /// 가능한 경우 하드웨어 가속을 사용한다 (자동 판단)
    static let kHardwareAccelerationAuto = Self(rawValue: "auto")
    
    /// 하드웨어 가속을 사용하지 않는다
    static let kHardwareAccelerationFalse = Self(rawValue: "false")
}
