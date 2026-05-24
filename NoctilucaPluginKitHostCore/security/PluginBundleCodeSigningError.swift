//
//  PluginBundleCodeSigningError.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation

/// CodeSigningVerifier 가 보안 정책 위반을 신호하기 위해 사용하는 에러 타입.
///
/// server-side 의 `PluginBundleRegistryError` 와 분리되어 있으며, server 는
/// 본 타입을 자신의 도메인 에러로 wrap 하는 식으로 사용한다.
public enum PluginBundleCodeSigningError: Error, Sendable {
    /// 번들이 현재 정책을 충족하지 못함.
    case securityPolicyViolation(
        currentPolicy: PluginBundleSecurityPolicy,
        requiredPolicy: PluginBundleSecurityPolicy
    )
}
