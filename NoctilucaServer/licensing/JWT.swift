//
//  JWT.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/6/26.
//

import Foundation
import Security

enum JWTDecoderError: Error {
    case invalidPublicKey
    case invalidToken
    case unsupportedAlgorithm
    case invalidSignature
    case tokenExpired
}

struct JWTHeader: Decodable {
    let alg: String
    let typ: String
}

private struct JWTExpClaim: Decodable {
    let exp: Int?
}

class JWTDecoder {
    static func parseDERRSAKey(_ derData: Data) -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 4096
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            return nil
        }

        return secKey
    }

    /// Base64url 문자열을 표준 Base64 Data로 디코딩한다.
    /// JWT는 URL-safe Base64 (RFC 4648 §5)를 사용하며, 패딩이 생략될 수 있다.
    static func decodeBase64url(_ base64url: String) -> Data? {
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }

    private let publicKey: SecKey

    init(_ publicKeyDER: Data) throws {
        guard let publicKey = Self.parseDERRSAKey(publicKeyDER) else {
            throw JWTDecoderError.invalidPublicKey
        }

        self.publicKey = publicKey
    }

    func decode<T>(_ jwt: String, as type: T.Type) -> Result<T, JWTDecoderError> where T: Decodable {
        let segments = jwt.split(separator: ".", maxSplits: 3).map(String.init)
        guard segments.count == 3 else {
            return .failure(.invalidToken)
        }

        guard let headerData = Self.decodeBase64url(segments[0]),
              let payloadData = Self.decodeBase64url(segments[1]),
              let signatureData = Self.decodeBase64url(segments[2]),

              let jsonHeader = String(data: headerData, encoding: .utf8),
              let jsonPayload = String(data: payloadData, encoding: .utf8),

              let header = try? JSON.parse(jsonHeader, to: JWTHeader.self),
              let payload = try? JSON.parse(jsonPayload, to: type)
        else {
            return .failure(.invalidToken)
        }

        // RS256 알고리즘만 지원
        guard header.alg == "RS256" else {
            return .failure(.unsupportedAlgorithm)
        }

        // exp 만료 체크 (필드가 있는 경우에만)
        if let expClaim = try? JSON.parse(jsonPayload, to: JWTExpClaim.self),
           let exp = expClaim.exp {
            let expirationDate = Date(timeIntervalSince1970: TimeInterval(exp))
            if expirationDate < Date.now {
                return .failure(.tokenExpired)
            }
        }

        // 서명 검증: 입력은 "base64url(header).base64url(payload)"의 UTF-8 바이트
        let signedInput = "\(segments[0]).\(segments[1])"
        guard let signedInputData = signedInput.data(using: .utf8) else {
            return .failure(.invalidToken)
        }

        let secAlgorithm: SecKeyAlgorithm = .rsaSignatureMessagePKCS1v15SHA256

        var error: Unmanaged<CFError>?
        guard SecKeyVerifySignature(publicKey, secAlgorithm, signedInputData as CFData, signatureData as CFData, &error) else {
            return .failure(.invalidSignature)
        }

        return .success(payload)
    }

}
