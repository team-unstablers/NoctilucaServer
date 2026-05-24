//
//  XPCPeerCodeSigningError.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/18/26.
//

import Foundation

/// XPC peer 의 code signing 동일성 검증 (`XPCPeerIdentity.verify(...)`) 이
/// 실패했을 때 사용하는 에러 타입.
///
/// `PluginBundleCodeSigningError` 가 *번들 자체* 의 서명을 다루는 것과 달리,
/// 본 타입은 *XPC connection 의 상대편 프로세스* 가 기대한 코드 서명 동일성을
/// 갖는지 평가하는 경계에서 발생한 실패를 표현한다.
public enum XPCPeerCodeSigningError: Error, Sendable {

    /// `SecRequirementCreateWithString` 가 DR 문자열을 파싱하지 못함.
    /// DR 문자열 자체가 오타 / 잘못된 구문일 때 발생.
    case requirementParseFailed(OSStatus)

    /// audit token 으로부터 `SecCode` 를 얻지 못함
    /// (`SecCodeCopyGuestWithAttributes` 실패). peer 프로세스가 이미 종료되어
    /// 사라졌거나, audit token 이 손상되었을 때 발생.
    case peerCodeUnavailable(OSStatus)

    /// `SecCodeCheckValidity` 가 DR 매칭을 거부함. peer 가 기대한 서명을
    /// 갖고 있지 않거나, 서명 자체가 무효함.
    case codeRejected(OSStatus)
}
