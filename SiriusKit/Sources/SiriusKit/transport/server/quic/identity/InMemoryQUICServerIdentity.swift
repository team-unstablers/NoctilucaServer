//
//  InMemoryQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit
import _CryptoExtras

internal import SwiftASN1
internal import X509
import SiriusKitCore

#if DEBUG

/// 테스트 용도로만 사용되는 QUICServerIdentity 구현체입니다.
internal class InMemoryQUICServerIdentity: QUICServerIdentity {
    private let identity: SecIdentity

    internal required init(_ identity: SecIdentity) {
        self.identity = identity
    }

    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        let security = SRSecurity.shared
        let keychain = SRKeychain.shared

        // 1. 충돌 여부를 확인한다
        guard !(try keychain.queryIdentityExistence(by: args.identityLabel).get()) else {
            throw QUICServerIdentityCreationError.identityAlreadyExists
        }

        do {
            // 2. cert-key pair를 생성한다
            let (certificate, privateKey) = try SelfSignedCertificateBuilder.createCertificateAndKey(args: args)

            // 3. secCertificate, secPrivateKey 생성한다
            let secCertificate = try security.createCertificate(using: certificate).get()
            let applicationLabel = try secCertificate.extractApplicationLabel()

            let secPrivateKey: SecKey
            let keyAttributes: [String: Any] = [
                kSecAttrKeyType as String: args.keyType.secKeyType,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: args.keyType.keySizeInBits,
                kSecAttrLabel as String: args.identityLabel,
                kSecAttrApplicationLabel as String: applicationLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrIsExtractable as String: true
            ]

            switch privateKey {
            case .p256(let key):
                secPrivateKey = try security.createPrivateKey(from: key, with: applicationLabel).get()
            case .rsa(let key):
                secPrivateKey = try security.createRSAPrivateKey(from: key, with: applicationLabel).get()
            }

            // keychain에 저장한다
            try keychain.addTemporaryItem(secCertificate, clazz: .certificate, label: args.identityLabel).get()
            try keychain.addTemporaryItem(secPrivateKey, clazz: .privateKey, label: args.identityLabel, extras: keyAttributes).get()

            // 4. 신뢰 설정 적용
            try security.trustCertificate(secCertificate, scope: .user).get()

            // 5. SecIdentity 생성
            // 이거 꼭 필요한가?
            let identity = try security.createIdentity(certificate: secCertificate, privateKey: secPrivateKey).get()

            return Self(identity)
        } catch {
            // cleanup
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .certificate).get()
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .privateKey, extras: [
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
            ]).get()

            throw error
        }
    }

    public func getServerIdentity() async throws -> SecIdentity {
        return identity
    }
}

#endif
