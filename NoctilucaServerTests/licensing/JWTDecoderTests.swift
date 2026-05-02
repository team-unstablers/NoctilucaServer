//
//  JWTDecoderTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 3/6/26.
//

import XCTest
import Security
@testable import NoctilucaServerTestsHost

final class JWTDecoderTests: XCTestCase {

    // MARK: - Test Helpers

    /// 테스트용 RSA 4096-bit 키페어를 동적 생성한다.
    private static func generateRSAKeyPair() -> (publicKey: SecKey, privateKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 4096
        ]

        var error: Unmanaged<CFError>?
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)!
        let publicKey = SecKeyCopyPublicKey(privateKey)!

        return (publicKey, privateKey)
    }

    /// SecKey(공개키)를 DER 바이트로 변환한다.
    private static func exportDER(_ key: SecKey) -> Data {
        var error: Unmanaged<CFError>?
        let data = SecKeyCopyExternalRepresentation(key, &error)! as Data
        return data
    }

    /// Base64url 인코딩 (패딩 제거)
    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 주어진 privateKey로 RS256 서명된 JWT를 생성한다.
    private static func createJWT(
        header: [String: Any] = ["alg": "RS256", "typ": "JWT"],
        payload: [String: Any],
        privateKey: SecKey
    ) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)

        let headerB64 = base64urlEncode(headerData)
        let payloadB64 = base64urlEncode(payloadData)

        let signedInput = "\(headerB64).\(payloadB64)"
        let signedInputData = signedInput.data(using: .utf8)!

        var error: Unmanaged<CFError>?
        let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signedInputData as CFData,
            &error
        )! as Data

        let signatureB64 = base64urlEncode(signature)
        return "\(headerB64).\(payloadB64).\(signatureB64)"
    }

    // MARK: - Shared Fixtures

    nonisolated(unsafe) private static let keyPair = generateRSAKeyPair()
    nonisolated(unsafe) private static let publicKeyDER = exportDER(keyPair.publicKey)

    private func makeDecoder() throws -> JWTDecoder {
        try JWTDecoder(Self.publicKeyDER)
    }

    // MARK: - 정상 디코딩

    func testDecodeValidJWT() throws {
        let decoder = try makeDecoder()
        let jwt = Self.createJWT(
            payload: [
                "iss": "test",
                "sub": "HWID-TEST",
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": "abc-123",
                "x-noc-license-id": "lic-001",
                "x-noc-seat-label": "test-seat"
            ],
            privateKey: Self.keyPair.privateKey
        )

        let result = decoder.decode(jwt, as: LicenseSeatProof.self)
        switch result {
        case .success(let proof):
            XCTAssertEqual(proof.iss, "test")
            XCTAssertEqual(proof.sub, "HWID-TEST")
            XCTAssertEqual(proof.licenseId, "lic-001")
            XCTAssertEqual(proof.hwid, "HWID-TEST")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    // MARK: - 잘못된 토큰 포맷

    func testDecodeInvalidTokenFormat() throws {
        let decoder = try makeDecoder()

        // segment 부족
        let result1 = decoder.decode("abc.def", as: LicenseSeatProof.self)
        XCTAssertEqual(result1.error, .invalidToken)

        // 빈 문자열
        let result2 = decoder.decode("", as: LicenseSeatProof.self)
        XCTAssertEqual(result2.error, .invalidToken)
    }

    // MARK: - 잘못된 서명

    func testDecodeInvalidSignature() throws {
        let decoder = try makeDecoder()
        let otherKeyPair = Self.generateRSAKeyPair()

        let jwt = Self.createJWT(
            payload: [
                "iss": "test",
                "sub": "HWID-TEST",
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": "abc-123",
                "x-noc-license-id": "lic-001"
            ],
            privateKey: otherKeyPair.privateKey // 다른 키로 서명
        )

        let result = decoder.decode(jwt, as: LicenseSeatProof.self)
        XCTAssertEqual(result.error, .invalidSignature)
    }

    // MARK: - RS256 외 알고리즘 거부

    func testDecodeRejectsNonRS256Algorithm() throws {
        let decoder = try makeDecoder()

        // HS256 헤더로 JWT 생성 (서명은 RS256으로 하지만 헤더만 변경)
        let jwt = Self.createJWT(
            header: ["alg": "HS256", "typ": "JWT"],
            payload: [
                "iss": "test",
                "sub": "HWID-TEST",
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": "abc-123",
                "x-noc-license-id": "lic-001"
            ],
            privateKey: Self.keyPair.privateKey
        )

        let result = decoder.decode(jwt, as: LicenseSeatProof.self)
        XCTAssertEqual(result.error, .unsupportedAlgorithm)
    }

    // MARK: - 만료된 토큰 거부

    func testDecodeRejectsExpiredToken() throws {
        let decoder = try makeDecoder()

        let jwt = Self.createJWT(
            payload: [
                "iss": "test",
                "sub": "HWID-TEST",
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970) - 7200,
                "exp": Int(Date.now.timeIntervalSince1970) - 3600, // 1시간 전 만료
                "jti": "abc-123",
                "x-noc-license-id": "lic-001"
            ],
            privateKey: Self.keyPair.privateKey
        )

        let result = decoder.decode(jwt, as: LicenseSeatProof.self)
        XCTAssertEqual(result.error, .tokenExpired)
    }

    // MARK: - exp 없는 토큰 허용

    func testDecodeAllowsTokenWithoutExp() throws {
        let decoder = try makeDecoder()

        let jwt = Self.createJWT(
            payload: [
                "iss": "test",
                "sub": "HWID-TEST",
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": "abc-123",
                "x-noc-license-id": "lic-001"
            ],
            privateKey: Self.keyPair.privateKey
        )

        let result = decoder.decode(jwt, as: LicenseSeatProof.self)
        switch result {
        case .success:
            break // exp 없이도 성공해야 함
        case .failure(let error):
            XCTFail("Expected success without exp, got \(error)")
        }
    }

    // MARK: - 유효한 exp 토큰 허용

    func testDecodeAllowsTokenWithFutureExp() throws {
        let decoder = try makeDecoder()

        let jwt = Self.createJWT(
            payload: [
                "iss": "test",
                "sub": "HWID-TEST",
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "exp": Int(Date.now.timeIntervalSince1970) + 3600, // 1시간 후 만료
                "jti": "abc-123",
                "x-noc-license-id": "lic-001"
            ],
            privateKey: Self.keyPair.privateKey
        )

        let result = decoder.decode(jwt, as: LicenseSeatProof.self)
        switch result {
        case .success(let proof):
            XCTAssertEqual(proof.iss, "test")
        case .failure(let error):
            XCTFail("Expected success with future exp, got \(error)")
        }
    }
}

// MARK: - Result Equatable Helper

private extension Result where Failure == JWTDecoderError {
    var error: JWTDecoderError? {
        switch self {
        case .success: return nil
        case .failure(let e): return e
        }
    }
}

extension JWTDecoderError: Equatable {}
