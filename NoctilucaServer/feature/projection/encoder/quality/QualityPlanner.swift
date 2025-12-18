//
//  QualityPlanner.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/18/25.
//

import SiriusKit

/// # 임시 품질 저하
/// 다음 상황에 해당할 때, 품질 저하를 고려할 수 있습니다.
/// - 소켓 backpressure가 잦은 경우
/// - 프레임 드롭이 잦은 경우
enum QualityDegradation: Hashable {
    /// 해상도를 낮춥니다. scale은 0.75 ~ 1.0 사이의 값입니다.
    case lowerResolution(scale: Float)
    /// 프레임 레이트를 낮춥니다. to는 목표 프레임 레이트입니다.
    case lowerFrameRate(to: Float)
}

protocol QualityPlanner {
    /// 품질 디그레이드를 허용합니다.
    var allowDegradation: Bool { get set }
    
    init(codec: CodecFourCC, resolution: CGSize, frameRate: Float)
    
    /// 퍼포먼스 리포트를 보고합니다.
    func feed(report: ProjectionPerformanceReport)
    
    /// 소켓 백프레셔 상태를 보고합니다.
    func feed(backpressure: Bool)
    
    func targetBitrateKbps() -> Int
    func maxBitrateKbps() -> Int
    
    func plannedDegradations() -> [QualityDegradation]
}


