//
//  CodecSpecification+default.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/31/26.
//

import Foundation
import SiriusKitClient

extension CodecSpecification {
    static let defaultSpecifications: [CodecSpecification] = [
        .hevc,
        .h264,
        .webp,
        .mjpg,
        .zrle
    ]
}
