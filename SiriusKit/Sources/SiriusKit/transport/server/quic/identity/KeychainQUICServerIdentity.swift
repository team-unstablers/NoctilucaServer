//
//  KeychainQUICServerIdentity.swift
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

public final class KeychainQUICServerIdentity: QUICServerIdentity {
    private static let logger = SiriusLogger(category: "KeychainQUICServerIdentity")
    private let identityLabel: String

    /// NOTE:
    ///   - assert(commonName == identityLabel) 안 그러면 조회 실패함. identityLabel에 다른 값을 넣을 생각 하지 마세요
    public required init(_ identityLabel: String) {
        self.identityLabel = identityLabel
    }
    
    public static func checkIdentityExistence(label: String) throws -> Bool {
        let keychain = SRKeychain.shared
        let existsResult = keychain.queryIdentityExistence(by: label)

        return try existsResult.get()
    }
    
    public static func checkIdentityUniqueness(label: String) throws -> Bool {
        let keychain = SRKeychain.shared
        let certsResult = keychain.queryItems(by: label, clazz: .certificate)

        let certs = try certsResult.get()
        return certs.count <= 1
    }

    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        let security = SRSecurity.shared
        let keychain = SRKeychain.shared

        /*
        // 1. 충돌 여부를 확인한다
        guard !(try keychain.queryIdentityExistence(by: args.identityLabel).get()) else {
            throw QUICServerIdentityCreationError.identityAlreadyExists
        }
         */
        
        if let existingCerts = try? keychain.queryItems(by: args.identityLabel, clazz: .certificate).get() {
            for cert in existingCerts {
                // swiftlint:disable:next force_cast
                let secCert = cert as! SecCertificate
                do {
                    let applicationLabel = try secCert.extractApplicationLabel()
                    _ = try keychain.deleteItem(by: args.identityLabel, clazz: .privateKey, extras: [
                        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                        kSecAttrApplicationLabel as String: applicationLabel
                    ]).get()
                } catch {
                    // 삭제 실패해도 일단 넘어감. 어차피 cert도 삭제할 거라 private key가 남아있는다고 해서 큰 문제는 없을 것 같음
                    Self.logger.error("Failed to delete existing private key for identity '\(args.identityLabel)'. Error: \(error)")
                }
            }
            
            do {
                _ = try keychain.deleteItems(references: existingCerts, clazz: .certificate).get()
            } catch {
                Self.logger.error("Failed to delete existing certificates for identity '\(args.identityLabel)'. Error: \(error)")
            }
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
            try keychain.addItem(secCertificate, clazz: .certificate, label: args.identityLabel).get()
            try keychain.addItem(secPrivateKey, clazz: .privateKey, label: args.identityLabel, extras: keyAttributes).get()

            // 4. 신뢰 설정 적용
            try security.trustCertificate(secCertificate, scope: .user).get()

            // 5. SecIdentity 생성
            // 이거 꼭 필요한가?
            _ = try security.createIdentity(certificate: secCertificate, privateKey: secPrivateKey).get()

            return Self(args.identityLabel)
        } catch {
            Self.logger.error("Failed to create self-signed identity for label '\(args.identityLabel)'. Error: \(error). Attempting cleanup.")
            
            // cleanup
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .certificate).get()
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .privateKey, extras: [
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
            ]).get()
            
            throw error
        }
    }
    
    public func checkExistence() async throws {
        guard try Self.checkIdentityUniqueness(label: self.identityLabel) else {
            throw QUICServerIdentityLoadError.conflictingIdentitiesFound
        }

        guard try Self.checkIdentityExistence(label: self.identityLabel) else {
            throw QUICServerIdentityLoadError.identityNotFound
        }
    }

    public func getServerIdentity() async throws -> SecIdentity {
        let keychain = SRKeychain.shared
    
        // 아이덴티티 충돌하지 않음을 보장해야 함
        try await self.checkExistence()
       
        let identityResult = keychain.queryIdentity(by: self.identityLabel)

        if case .failure(let error) = identityResult {
            throw error
        }

        let identity = try identityResult.get()

        return identity
    }

    public func getCertificateChain() async throws -> [SecCertificate] {
        let leaf = try await self.secCertificate()
        let trust = try SecTrust.create(leaf: leaf, isServer: true, allowSelfSigned: false)

        // 체인 구성이 가능하면 신뢰 평가 결과와 무관하게 leaf를 제외한 체인을 추출합니다.
        _ = try? trust.evaluate()

        guard let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              certificateChain.count > 1
        else {
            return []
        }

        return Array(certificateChain.dropFirst())
    }
}
