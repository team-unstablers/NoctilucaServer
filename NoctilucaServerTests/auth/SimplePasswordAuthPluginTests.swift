//
//  SimplePasswordAuthPluginTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 4/30/26.
//

import XCTest

import NoctilucaPluginKit
@testable import NoctilucaServerTestsHost

final class SimplePasswordAuthPluginTests: XCTestCase {

    // MARK: - method 검증

    /// `.simplePassword` 외의 method 는 `.unsupportedMethod` 로 거부되어야 한다.
    func testAuthenticateRejectsUnsupportedMethod() async {
        let plugin = SimplePasswordAuthPlugin()

        let result = await plugin.authenticate(
            using: .password,
            payload: Data("password".utf8),
            nonce: Data()
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        guard case .unsupportedMethod = error else {
            return XCTFail("expected .unsupportedMethod, got \(error)")
        }
    }

    // MARK: - payload NUL byte 차단 (NCH-002 F-1 / S-204)

    /// payload 에 NUL byte 가 포함된 경우 `.invalidPayload` 를 반환해야 한다.
    /// 본 플러그인은 payload 를 UTF-8 텍스트 password 로 가정하며,
    /// NUL 포함 payload 는 bcrypt_sha512 의 strlen() 기반 truncation 으로 인해
    /// 서로 다른 password 가 동일 hash 로 매핑되는 무결성 결함을 유발한다.
    func testAuthenticateRejectsPayloadContainingNullByte() async {
        let plugin = SimplePasswordAuthPlugin()
        let payloadWithNull = Data([0x70, 0x00, 0x71])  // "p\0q"

        let result = await plugin.authenticate(
            using: .simplePassword,
            payload: payloadWithNull,
            nonce: Data()
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        guard case .invalidPayload = error else {
            return XCTFail("expected .invalidPayload, got \(error)")
        }
    }

    /// Trailing NUL byte 도 `.invalidPayload` 로 거부되어야 한다.
    func testAuthenticateRejectsPayloadWithTrailingNullByte() async {
        let plugin = SimplePasswordAuthPlugin()
        let payloadWithTrailingNull = Data([0x61, 0x62, 0x00])  // "ab\0"

        let result = await plugin.authenticate(
            using: .simplePassword,
            payload: payloadWithTrailingNull,
            nonce: Data()
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        guard case .invalidPayload = error else {
            return XCTFail("expected .invalidPayload, got \(error)")
        }
    }

    /// `.invalidPayload` 분기는 `.authenticationFailed` 보다 *먼저* 반환되어야 한다.
    /// allowedHashes 가 비어있으면 어차피 `.authenticationFailed` 가 나오므로,
    /// 빈 상태에서도 NUL payload 는 `.invalidPayload` 로 분류되는지 검증한다.
    func testInvalidPayloadTakesPrecedenceOverAuthenticationFailed() async {
        let plugin = SimplePasswordAuthPlugin()
        // allowedHashes 가 비어있는 상태에서, NUL 없는 payload → .authenticationFailed,
        //                                    NUL 포함 payload → .invalidPayload
        // 둘이 분명히 분기되는지 비교 검증.

        let payloadWithNull = Data([0x00])
        let payloadWithoutNull = Data("password".utf8)

        let resultWithNull = await plugin.authenticate(
            using: .simplePassword,
            payload: payloadWithNull,
            nonce: Data()
        )
        let resultWithoutNull = await plugin.authenticate(
            using: .simplePassword,
            payload: payloadWithoutNull,
            nonce: Data()
        )

        guard case .failure(let errorWithNull) = resultWithNull,
              case .invalidPayload = errorWithNull
        else {
            return XCTFail("expected .invalidPayload for NUL payload, got \(resultWithNull)")
        }

        guard case .failure(let errorWithoutNull) = resultWithoutNull,
              case .authenticationFailed = errorWithoutNull
        else {
            return XCTFail("expected .authenticationFailed for normal payload (empty allowedHashes), got \(resultWithoutNull)")
        }
    }

    // MARK: - 정상 인증 회귀 방지

    /// 등록된 hash 에 매칭되는 payload 는 정상적으로 `.success(uid)` 를 반환해야 한다.
    /// NUL 차단 로직이 정상 인증 흐름까지 깨뜨리는 회귀를 방지한다.
    func testAuthenticateSucceedsForRegisteredPassword() async throws {
        let plugin = SimplePasswordAuthPlugin()
        let password = Data("correct-horse-battery-staple".utf8)

        // 등록 경로와 동일하게 sha512 → bcrypt hash 처리.
        let digest = try Bcrypt.sha512(value: password)
        let hash = try Bcrypt.hash(password: digest)

        let entry = AuthEntry(
            method: .simplePassword,
            identifier: "bcrypt+sha512",
            data: hash
        )
        try await plugin.allow(entry)

        let result = await plugin.authenticate(
            using: .simplePassword,
            payload: password,
            nonce: Data()
        )

        guard case .success(let uid) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(uid, getuid())
    }

    /// 등록되지 않은 password 는 `.authenticationFailed` 로 거부되어야 한다.
    func testAuthenticateFailsForWrongPassword() async throws {
        let plugin = SimplePasswordAuthPlugin()

        let registeredPassword = Data("correct-password".utf8)
        let digest = try Bcrypt.sha512(value: registeredPassword)
        let hash = try Bcrypt.hash(password: digest)
        try await plugin.allow(AuthEntry(method: .simplePassword, identifier: "bcrypt+sha512", data: hash))

        let result = await plugin.authenticate(
            using: .simplePassword,
            payload: Data("wrong-password".utf8),
            nonce: Data()
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        guard case .authenticationFailed = error else {
            return XCTFail("expected .authenticationFailed, got \(error)")
        }
    }
}
