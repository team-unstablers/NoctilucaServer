//
//  SystemCapability+HDR.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/1/26.
//

extension SystemCapability {
    struct HDR {
        /// ScreenCaptureKit이 HDR 캡쳐를 지원하는지 여부를 반환합니다.
        static var screenCaptureKitSupportsHDRCapture: Bool {
            // SCStreamConfiguration(preset:)은 macOS 15.0부터 사용할 수 있습니다.
            if #available(macOS 15.0, *) {
                true
            } else {
                false
            }
        }
    }
}
