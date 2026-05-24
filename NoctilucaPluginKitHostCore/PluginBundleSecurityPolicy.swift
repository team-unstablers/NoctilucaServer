//
//  PluginBundleSecurityPolicy.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

/// Plugin Bundle에 대한 보안 정책
public enum PluginBundleSecurityPolicy: String, Codable, Sendable {
    /// Noctiluca Server에 부속된 것 이외의 모든 플러그인 번들 로드를 거부합니다.
    case disallowAll = "disallowAll"

    /// Noctiluca 개발사인 team unstablers Inc. 에서 제공하는 플러그인 번들을 허용합니다.
    /// team unstablers Inc.는 Noctiluca Server 배포본 외에도 추가 플러그인을 제공할 수 있습니다.
    case allowTeamUnstablers = "allowTeamUnstablers"

    /// Apple 개발자 프로그램을 통해 서명된 제 3자의 플러그인 번들을 허용합니다.
    /// NOTE: Apple로부터 서명을 받았다고 해서 반드시 안전한 플러그인이라는 보장은 없습니다!!
    case allowSigned = "allowSigned"

    /// Ad-hoc으로 서명된 플러그인 번들을 포함하여 모든 플러그인 번들을 허용합니다.
    /// NOTE: 악성 플러그인에 의해 시스템이 손상될 가능성이 있습니다!
    case allowAll = "allowAll"
}
