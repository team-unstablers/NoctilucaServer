//
//  XPCPeerIdentityTests.swift
//  NoctilucaPluginKitHostCoreTests
//
//  Created by Gyuhwan Park on 5/18/26.
//

import XCTest
import Security
@testable import NoctilucaPluginKitHostCore

/// `XPCPeerIdentity` 의 *형태 / 계약* 만 검증한다.
///
/// 실제 양 끝 peer 매칭 ("이 audit token 의 프로세스가 정말로 서명된
/// NoctilucaServer.app 이다") 은 codesign 된 바이너리 + 실제 XPC connection 이
/// 필요하기 때문에 단위 테스트로는 다루지 않는다. 통합 시나리오는
/// `NoctilucaPluginKitHost` 본 프로세스를 launchd 가 spawn 했을 때만 의미
/// 있는 검증이다.
final class XPCPeerIdentityTests: XCTestCase {

    // MARK: - DR string sanity

    /// 코드에 박혀 있는 DR 문자열이 Code Signing Requirement Language 로
    /// 파싱 가능한지 (오타 / 따옴표 누락 등) 확인한다. 이게 깨지면 실 동작에서
    /// `XPCPeerCodeSigningError.requirementParseFailed` 가 *모든* connection
    /// 에서 발생하므로 가장 먼저 잡혀야 하는 회귀이다.
    func testServerPeerRequirementParses() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            XPCPeerIdentity.serverPeerRequirement as CFString,
            [],
            &requirement
        )
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    func testHostPeerRequirementParses() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            XPCPeerIdentity.hostPeerRequirement as CFString,
            [],
            &requirement
        )
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    /// 두 DR 문자열에 핵심 토큰이 모두 포함되어 있는지를 확인. 누군가
    /// "anchor apple generic" 같은 핵심 조건을 실수로 지웠을 때를 잡기 위한
    /// 매우 얕은 회귀 가드.
    func testDesignatedRequirementsContainExpectedClauses() {
        for dr in [
            XPCPeerIdentity.serverPeerRequirement,
            XPCPeerIdentity.hostPeerRequirement
        ] {
            XCTAssertTrue(dr.contains("anchor apple generic"))
            XCTAssertTrue(dr.contains("XHA76UVA95"))
            XCTAssertTrue(dr.contains("certificate leaf[subject.OU]"))
        }
        XCTAssertTrue(
            XPCPeerIdentity.serverPeerRequirement.contains("app.noctiluca.server\"")
        )
        XCTAssertTrue(
            XPCPeerIdentity.hostPeerRequirement.contains(
                "app.noctiluca.server.NoctilucaPluginKitHost\""
            )
        )
    }

    // MARK: - verify(auditToken:) behaviour

    /// 파싱 불가능한 DR 문자열을 넘기면 `requirementParseFailed` 로 떨어져야
    /// 한다. 잘못된 DR 이 silently `success` 로 통과되어선 안 된다.
    func testVerifyReportsRequirementParseFailure() {
        let nonsenseDR = "this is not a valid requirement string"
        let dummyToken = Data(repeating: 0, count: 32)

        let result = XPCPeerIdentity.verify(
            auditToken: dummyToken,
            designatedRequirement: nonsenseDR
        )

        switch result {
        case .failure(.requirementParseFailed):
            break
        default:
            XCTFail("expected requirementParseFailed, got \(result)")
        }
    }

    /// `audit_token_t` 크기 (32 bytes) 의 0-filled 토큰은 존재하는 어떤
    /// 프로세스도 가리키지 않는다. `SecCodeCopyGuestWithAttributes` 가 peer
    /// 의 `SecCode` 를 얻지 못해 `peerCodeUnavailable` 또는 `codeRejected` 로
    /// 떨어져야 하며, 어느 경우든 `success` 는 반환되지 않아야 한다.
    func testVerifyRejectsZeroedAuditToken() {
        let dummyToken = Data(repeating: 0, count: 32)
        let result = XPCPeerIdentity.verify(
            auditToken: dummyToken,
            designatedRequirement: XPCPeerIdentity.serverPeerRequirement
        )

        switch result {
        case .success:
            XCTFail("zeroed audit token must not satisfy any DR")
        case .failure(.requirementParseFailed):
            XCTFail("DR string itself parsed fine; failure must be downstream")
        case .failure:
            // peerCodeUnavailable / codeRejected 어느 쪽이든 reject 면 OK.
            break
        }
    }
}
