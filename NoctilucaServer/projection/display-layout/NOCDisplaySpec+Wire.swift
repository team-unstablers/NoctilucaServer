//
//  NOCDisplaySpec+Wire.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation
import CoreGraphics

import SiriusKit

extension NOCDisplaySpec {
    init(from siriusSpec: SiriusKit.DisplaySpec) {
        let resolution = CGSize(
            width: siriusSpec.resolution?.width ?? 0,
            height: siriusSpec.resolution?.height ?? 0
        )
        let scale = siriusSpec.scaleFactor > 0 ? siriusSpec.scaleFactor : 1.0

        var metadata: [NOCDisplaySpecMetadataKey: String] = [:]
        for (key, value) in siriusSpec.metadata {
            metadata[NOCDisplaySpecMetadataKey(rawValue: key)] = value
        }

        self.init(
            resolution: resolution,
            refreshRate: siriusSpec.refreshRate,
            scaleFactor: CGFloat(scale),
            metadata: metadata
        )
    }

    func toSiriusSpec() -> SiriusKit.DisplaySpec {
        let metadata = Dictionary(uniqueKeysWithValues: metadata.map { ($0.key.rawValue, $0.value) })

        return SiriusKit.DisplaySpec(
            resolution: SRSize(width: Double(resolution.width), height: Double(resolution.height)),
            refreshRate: refreshRate,
            scaleFactor: Double(scaleFactor),
            metadata: metadata
        )
    }
}
