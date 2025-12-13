//
//  CodecOptionValue+ColorFormat.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

extension CodecOptionValue {
    /// 가능한 경우 하드웨어 가속을 사용한다
    static let kHardwareAccelerationTrue = Self(rawValue: "true")
    
    /// 하드웨어 가속을 사용하지 않는다
    static let kHardwareAccelerationFalse = Self(rawValue: "false")
    
    /// 강제 하드웨어 가속 사용
    static let kHardwareAccelerationForced = Self(rawValue: "forced")
}
