//
//  TestConfig.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation

fileprivate func getenv(_ name: String, default defaultValue: String? = nil) -> String? {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        return defaultValue
    }
    return value
}

struct TestConfig {
    /// 무인 테스트 환경임을 알립니다.
    /// 무인 테스트 환경에서는 사용자 입력을 요구하는 다음 테스트를 건너뜁니다:
    ///   - **QUIC 프로토콜 관련 테스트**: 테스트 준비 과정에서 자가 서명 인증서를 신뢰하기 위해 사용자 인증 정보를 묻는 대화 상자가 나타나기 때문에 무인 환경에서는 이 테스트를 건너뜁니다.
    static let isUnattended: Bool = getenv("SIRIUSKIT_TEST_IS_UNATTENDED", default: "0")!.lowercased() == "1"
}
