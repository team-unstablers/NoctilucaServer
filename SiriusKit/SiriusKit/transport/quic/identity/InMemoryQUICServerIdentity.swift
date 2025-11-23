//
//  InMemoryQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit

import SwiftASN1
import X509

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
        guard !(try keychain.queryIdentityExistance(by: args.identityLabel).get()) else {
            throw QUICServerIdentityCreationError.identityAlreadyExists
        }
        
        do {
            // 2. cert-key pair를 생성한다
            let (certificate, privateKey) = try SelfSignedCertificateBuilder.createCertificateAndKey(args: args)
            
            // 3. secCertificate, secPrivateKey 생성한다
            let secCertificate = try security.createCertificate(using: certificate).get()
            let applicationLabel = try secCertificate.extractApplicationLabel()
            
            let secPrivateKey = try security.createPrivateKey(from: privateKey, with: applicationLabel).get()
            
            // keychain에 저장한다
            try keychain.addTemporaryItem(secCertificate, clazz: .certificate, label: args.identityLabel).get()
            try keychain.addTemporaryItem(secPrivateKey, clazz: .privateKey, label: args.identityLabel, extras: [
                // 근데 여기서 필요 없는 프로퍼티가 있지 않을까?
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: 256,
                kSecAttrLabel as String: args.identityLabel,
                kSecAttrApplicationLabel as String: applicationLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]).get()
            
            // 4. 신뢰 설정 적용
            try security.trustCertificate(secCertificate, scope: .user).get()
            
            // 5. SecIdentity 생성
            // 이거 꼭 필요한가?
            let identity = try security.createIdentity(certificate: secCertificate, privateKey: secPrivateKey).get()
            
            return Self(identity)
        } catch {
            // cleanup
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .certificate).get()
            _ = try? keychain.deleteItem(by: args.identityLabel, clazz: .privateKey).get()
            
            throw error
        }
    }
    
    public func getServerIdentity() async throws -> sec_identity_t {
        return identity.castAsCHandle()
    }
}

#endif
