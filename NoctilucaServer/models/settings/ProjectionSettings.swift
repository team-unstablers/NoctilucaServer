//
//  ProjectionSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct Projection: Category {
        /// 사용자가 선호하는 화면 녹화기 구현체 순서.
        /// 잠금 화면 등에서는 AVFoundation 기반 녹화기로 폴백할 수 있습니다.
        var preferredScreenRecorder: ScreenRecorderType = .screenCaptureKit
        
        
        var codecSpecifications: [CodecSpecification] = [
            .hevc,
            .h264
        ]
    }
}
