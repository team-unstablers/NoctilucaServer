//
//  BcryptTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 4/30/26.
//

import XCTest

import libbcrypt
@testable import NoctilucaServerTestsHost

final class BcryptTests: XCTestCase {

    // MARK: - sha512: NUL byte 차단 (NCH-002 F-1 / S-204)

    /// `bcrypt_sha512()` 가 입력 길이를 `strlen(in)` 으로 측정하므로 NUL 포함 payload 는
    /// silently truncate 되어 서로 다른 password 가 동일 digest 로 매핑되는 무결성 결함이
    /// 발생한다. Swift wrapper 는 이를 입력 단계에서 차단해야 한다.
    func testSha512RejectsValueContainingNullByte() {
        let valueWithNull = Data([0x70, 0x00, 0x71])  // "p\0q"

        do {
            _ = try Bcrypt.sha512(value: valueWithNull)
            XCTFail("expected BcryptError.invalidInput, got success")
        } catch BcryptError.invalidInput {
            // expected
        } catch {
            XCTFail("expected BcryptError.invalidInput, got \(error)")
        }
    }

    /// Trailing NUL byte 도 동일하게 차단되어야 한다 — `strlen` 은 첫 NUL 에서 멈추므로
    /// 길이 계산이 *우연히* 정상으로 보일 수 있는 case 도 무결성 위반에 해당한다.
    func testSha512RejectsValueWithTrailingNullByte() {
        let valueWithTrailingNull = Data([0x61, 0x62, 0x00])  // "ab\0"

        XCTAssertThrowsError(try Bcrypt.sha512(value: valueWithTrailingNull)) { error in
            guard case BcryptError.invalidInput = error else {
                return XCTFail("expected BcryptError.invalidInput, got \(error)")
            }
        }
    }

    /// 첫 byte 가 NUL 인 경우도 차단되어야 한다. 이 case 는 `strlen` 이 0을 반환하여
    /// *어떤 입력이든* 동일 digest 로 매핑되는 가장 위험한 형태이다.
    func testSha512RejectsValueWithLeadingNullByte() {
        let valueWithLeadingNull = Data([0x00, 0x70, 0x71])  // "\0pq"

        XCTAssertThrowsError(try Bcrypt.sha512(value: valueWithLeadingNull)) { error in
            guard case BcryptError.invalidInput = error else {
                return XCTFail("expected BcryptError.invalidInput, got \(error)")
            }
        }
    }

    // MARK: - sha512: 정상 동작 회귀 방지

    /// NUL byte 가 없는 일반 UTF-8 password 는 그대로 처리되어야 한다.
    /// 차단 로직이 정상 입력까지 거부하는 회귀를 방지한다.
    func testSha512AcceptsValueWithoutNullByte() throws {
        let value = Data("password".utf8)

        let digest = try Bcrypt.sha512(value: value)

        XCTAssertEqual(digest.count, Int(BCRYPT_512BITS_BASE64_SIZE))
    }

    /// 동일 입력은 항상 동일 digest 를 반환해야 한다 (deterministic).
    func testSha512IsDeterministicForSameInput() throws {
        let value = Data("hello world".utf8)

        let digest1 = try Bcrypt.sha512(value: value)
        let digest2 = try Bcrypt.sha512(value: value)

        XCTAssertEqual(digest1, digest2)
    }

    /// 서로 다른 입력은 서로 다른 digest 를 생성해야 한다.
    /// (NUL 차단으로 인한 false positive 검증의 보조)
    func testSha512ProducesDifferentDigestForDifferentInputs() throws {
        let valueA = Data("alpha".utf8)
        let valueB = Data("beta".utf8)

        let digestA = try Bcrypt.sha512(value: valueA)
        let digestB = try Bcrypt.sha512(value: valueB)

        XCTAssertNotEqual(digestA, digestB)
    }

    // MARK: - sha512Async: 비동기 wrapper 동작 일관성

    /// `sha512Async` 도 동일하게 NUL 입력을 차단해야 한다.
    func testSha512AsyncRejectsValueContainingNullByte() async {
        let valueWithNull = Data([0x70, 0x00, 0x71])

        do {
            _ = try await Bcrypt.sha512Async(value: valueWithNull)
            XCTFail("expected BcryptError.invalidInput, got success")
        } catch BcryptError.invalidInput {
            // expected
        } catch {
            XCTFail("expected BcryptError.invalidInput, got \(error)")
        }
    }
}
