//
//  CodecOptionValue+ColorDepth.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/20/25.
//

extension CodecOptionValue {
    /// 디스플레이 밀도를 자동으로 선택합니다.
    static let kDisplayDensityAuto = Self(rawValue: "auto")
    
    /// 퍼포먼스에 가장 유리한 디스플레이 밀도를 선택합니다.
    static let kDisplayDensityPerformance = Self(rawValue: "performance")

    /// 최대한 좋은 디스플레이 밀도를 선택합니다.
    static let kDisplayDensityBest = Self(rawValue: "best")
}
