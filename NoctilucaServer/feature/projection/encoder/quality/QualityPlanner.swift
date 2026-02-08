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
    /// 인코딩 품질을 낮춥니다. factor는 0.0~1.0이며, 1.0이 원래 품질입니다.
    case lowerQuality(factor: Float)
    /// 양자화 레벨을 증가시킵니다. level은 0(없음)~5(최대) 사이의 절대값입니다.
    /// 여러 단계가 동시에 활성화된 경우 max()로 가장 높은 레벨만 적용합니다.
    case increaseQuantization(level: Int)
}

protocol QualityPlanner {
    /// 품질 디그레이드를 허용합니다.
    var allowDegradation: Bool { get set }
    
    init(codec: CodecFourCC, resolution: CGSize, frameRate: Float)
    
    /// 퍼포먼스 리포트를 보고합니다.
    func feed(report: ProjectionPerformanceReport)
    
    /// 큐 압력 비율 (0.0 = 비어있음 ~ 1.0 = 가득 참)을 보고합니다.
    func feed(queuePressure: Float)
    
    func targetBitrateKbps() -> Int
    func maxBitrateKbps() -> Int
    
    func plannedDegradations() -> [QualityDegradation]
}


