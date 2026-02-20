//
//  DaemonFeatureProvider.swift
//  noctilucad
//
//  Created by Claude on 2/20/26.
//

import SiriusKit

/// 데몬용 최소 FeatureProvider.
///
/// SiriusServerBuilder가 FeatureProvider를 요구하므로 제공하지만,
/// 실제 feature channel은 데몬에서 생성하지 않는다.
/// 인증 완료 후 에이전트에 핸드오프되기 때문에 createChannel은 호출되지 않아야 한다.
class DaemonFeatureProvider: FeatureProvider {
    func supportedFeatures() -> [SiriusFeature] {
        [.hidio, .projection]
    }

    func supports(_ feature: SiriusFeature) -> Bool {
        switch feature {
        case .hidio, .projection, .projectionData:
            return true
        default:
            return false
        }
    }

    func createChannel(
        for feature: SiriusFeature,
        using streamHolder: StreamHolder,
        identifier: ChannelIdentifier,
        direction: ChannelDirection,
        args: [String]
    ) -> Channel {
        // 데몬에서는 feature channel을 생성하지 않는다.
        // 인증 완료 후 에이전트에 핸드오프되므로, 이 메서드가 호출되면 로직 오류다.
        fatalError("DaemonFeatureProvider.createChannel should never be called — handoff should occur before channel creation")
    }
}
