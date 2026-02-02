//
//  KeychainQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit

import SwiftASN1
import X509

public class KeychainQUICServerIdentity: QUICServerIdentity {
    private let identityLabel: String

    /// NOTE:
    ///   - assert(commonName == identityLabel) 안 그러면 조회 실패함. identityLabel에 다른 값을 넣을 생각 하지 마세요
    public required init(_ identityLabel: String) {
        self.identityLabel = identityLabel
    }

    public static func checkIdentityExistance(label: String) throws -> Bool {
        let keychain = SRKeychain.shared
        let existsResult = keychain.queryIdentityExistance(by: label)

        return try existsResult.get()
    }

    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        let security = SRSecurity.shared
        let keychain = SRKeychain.shared

        /*
        // 1. 충돌 여부를 확인한다
        guard !(try keychain.queryIdentityExistance(by: args.identityLabel).get()) else {
            throw QUICServerIdentityCreationError.identityAlreadyExists
        }
         */

        if try keychain.queryIdentityExistance(by: args.identityLabel).get() {
            _ = try keychain.deleteItem(by: args.identityLabel, clazz: .identity).get()
            _ = try keychain.deleteItem(by: args.identityLabel, clazz: .certificate).get()
            _ = try keychain.deleteItem(by: args.identityLabel, clazz: .privateKey).get()
        }

        do {
            // 2. cert-key pair를 생성한다
            let (certificate, privateKey) = try SelfSignedCertificateBuilder.createCertificateAndKey(args: args)

            // 3. secCertificate, secPrivateKey 생성한다
            let secCertificate = try security.createCertificate(using: certificate).get()
            let applicationLabel = try secCertificate.extractApplicationLabel()

            let secPrivateKey = try security.createPrivateKey(from: privateKey, with: applicationLabel).get()

            // keychain에 저장한다
            try keychain.addItem(secCertificate, clazz: .certificate, label: args.identityLabel).get()
            try keychain.addItem(secPrivateKey, clazz: .privateKey, label: args.identityLabel, extras: [
                // 근데 여기서 필요 없는 프로퍼티가 있지 않을까?
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: 256,
                kSecAttrLabel as String: args.identityLabel,
                kSecAttrApplicationLabel as String: applicationLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]).get()

            // 4. 신뢰 설정 적용
            try security.trustCertificate(secCertificate, scope: .user).get()

            // 5. SecIdentity 생성
            // 이거 꼭 필요한가?
            _ = try security.createIdentity(certificate: secCertificate, privateKey: secPrivateKey).get()

            return Self(args.identityLabel)
        } catch {
            // cleanup
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .certificate).get()
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .privateKey).get()

            throw error
        }
    }

    public func getServerIdentity() async throws -> SecIdentity {
        let keychain = SRKeychain.shared
        let identityResult = keychain.queryIdentity(by: self.identityLabel)

        if case .failure(let error) = identityResult {
            throw error
        }

        let identity = try identityResult.get()

        return identity
    }
}
