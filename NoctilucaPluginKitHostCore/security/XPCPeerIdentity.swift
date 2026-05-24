//
//  XPCPeerIdentity.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/18/26.
//

import Foundation
import Security

/// NoctilucaServer ↔ NoctilucaPluginKitHost.xpc 사이 XPC 경계의 양 끝 peer
/// 가 *기대한 코드 서명 동일성* 을 갖고 있는지 검증하기 위한 헬퍼.
///
/// `RPCXPCEndpointOptions.peerCodeSigningRequirement` 는 libxpc 가 OS 레벨에서
/// DR 매칭을 수행하지만, Shotoku 의 `authorize:` 클로저 안에서 추가적인 앱-레벨
/// 게이트로 본 타입을 한 번 더 호출하여 *이중 가드* 를 형성한다 (`docs/xpc-safety.md`
/// §3.1 — "권장: 위에 더해 …이중 가드").
///
/// DR 문자열은 두 빌드 컨피그 (Debug `Apple Development` / Release
/// `Developer ID Application`) 모두에서 anchor / OU 가 동일하게 평가되므로
/// `#if DEBUG` 분기 없이 unconditional 으로 enforce 한다.
public enum XPCPeerIdentity {

    // MARK: - Designated Requirement strings

    /// `NoctilucaServer.app` 본체에 대한 Designated Requirement.
    ///
    /// host XPC service 의 listener 가, "내게 connect 해 온 peer 가 서명된
    /// Noctiluca 서버 본체가 맞는가" 를 확인할 때 사용한다.
    public static let serverPeerRequirement: String = """
identifier "app.noctiluca.server" \
and anchor apple generic \
and certificate leaf[subject.OU] = "XHA76UVA95"
"""

    /// `NoctilucaPluginKitHost.xpc` 에 대한 Designated Requirement.
    ///
    /// 서버 본체의 `XPCLoader` 가, "내가 connect 하려는 host XPC service 가
    /// 우리 번들 안에 동봉되어 서명된 그것인가" 를 확인할 때 사용한다.
    public static let hostPeerRequirement: String = """
identifier "app.noctiluca.server.NoctilucaPluginKitHost" \
and anchor apple generic \
and certificate leaf[subject.OU] = "XHA76UVA95"
"""

    // MARK: - Verification

    /// `audit_token_t` 원본 (`Shotoku.RPCPeerProcess.auditToken`) 을 받아,
    /// 그 토큰이 가리키는 peer process 의 라이브 코드 서명이 주어진 DR 을
    /// 만족하는지 검증한다.
    ///
    /// 흐름:
    ///   1. `SecRequirementCreateWithString` — DR 문자열 → `SecRequirement`.
    ///   2. `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit:)` —
    ///      audit token → 라이브 peer 의 `SecCode`.
    ///   3. `SecCodeCheckValidity` — peer 의 서명이 (a) 무결하고 (b) DR 에
    ///      매칭되는지 평가.
    ///
    /// - Parameters:
    ///   - auditToken: `audit_token_t` 의 32-byte 원본을 `Data` 로 wrapping
    ///     한 값. Shotoku 가 `xpc_dictionary_get_audit_token` /
    ///     `xpc_connection_get_audit_token` 결과를 그대로 채워서 넘긴다.
    ///   - designatedRequirement: Code Signing Requirement Language 문자열.
    ///     `XPCPeerIdentity.serverPeerRequirement` / `.hostPeerRequirement`
    ///     를 사용하거나, 호출자가 직접 작성한 문자열을 전달한다.
    public static func verify(
        auditToken: Data,
        designatedRequirement: String
    ) -> Result<Void, XPCPeerCodeSigningError> {

        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            designatedRequirement as CFString,
            [],
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            return .failure(.requirementParseFailed(requirementStatus))
        }

        var peerCode: SecCode?
        let attributes: [CFString: Any] = [
            kSecGuestAttributeAudit: auditToken as CFData
        ]
        let copyStatus = SecCodeCopyGuestWithAttributes(
            nil,
            attributes as CFDictionary,
            [],
            &peerCode
        )
        guard copyStatus == errSecSuccess, let peerCode else {
            return .failure(.peerCodeUnavailable(copyStatus))
        }

        let validityStatus = SecCodeCheckValidity(peerCode, [], requirement)
        guard validityStatus == errSecSuccess else {
            return .failure(.codeRejected(validityStatus))
        }

        return .success(())
    }
}
