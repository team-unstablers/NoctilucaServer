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
    
    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        // 충돌 여부 확인
        if identityExists(label: args.identityLabel) {
            throw QUICServerIdentityCreationError.identityAlreadyExists
        }
        
        let (certificate, privateKey) = try SelfSignedCertificateBuilder.createCertificateAndKey(args: args)
        
         // 4-1. SecCertificate 생성
        var derSerializer = DER.Serializer()
        
        try certificate.serialize(into: &derSerializer)
        
        let derData = derSerializer.serializedBytes
        let certData = Data(derData)
        guard let secCertificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw QUICServerIdentityCreationError.certificateCreationFailed
        }
        
        /*
         macOS의 Keychain은 물리적으로 SecIdentity라는 별도의 아이템을 저장하지 않습니다. 대신, 요청이 들어오면 아래 로직을 통해 동적으로 묶어줍니다.

             인증서(Certificate) 안에 있는 공개 키(Public Key)의 해시(Hash) 값을 계산합니다.

             키체인에 저장된 **개인 키(Private Key)**들 중에서, kSecAttrApplicationLabel 속성 값이 위에서 계산한 해시 값과 정확히 일치하는 키를 찾습니다.

             짝이 맞으면 이 둘을 합쳐서 SecIdentity 객체로 리턴합니다.
         */
        var trust: SecTrust?
        SecTrustCreateWithCertificates(secCertificate, SecPolicyCreateBasicX509(), &trust)
        
        guard let trustedTrust = trust,
                  let publicKey = SecTrustCopyKey(trustedTrust) else {
            throw QUICServerIdentityCreationError.certificateCreationFailed
        }
        
        let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any]
        let applicationLabel = attributes?[kSecAttrApplicationLabel as String] as? Data
        
        print(applicationLabel?.base64EncodedString())
        
        // 4-2. SecKey (Private Key) 생성
        // SecKeyCreateWithData는 PKCS#8 DER을 직접 받지 못하고, ANSI X9.63 형식의 개인키 데이터를 기대한다.
        let privateKeyData = privateKey.x963Representation
        
        // 5-1. 키체인에 인증서 저장
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCertificate,
            kSecAttrLabel as String: args.identityLabel,
            kSecAttrIsPermanent as String: true // 키체인 저장 여부
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            // best-effort cleanup of generated key on failure
            deletePrivateKey(label: args.identityLabel)
            
            if status == errSecDuplicateItem {
                throw QUICServerIdentityCreationError.identityAlreadyExists
            }
            throw QUICServerIdentityCreationError.keychainWriteFailed(status)
        }
        
        // 5-2. 키체인에 개인키 저장
        let keyTag = args.identityLabel.data(using: .utf8)!
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: args.identityLabel,
            kSecAttrApplicationLabel as String: applicationLabel, // <--- 여기가 핵심 연결 고리!
            kSecAttrIsPermanent as String: true, // 키체인 저장 여부
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        var error: Unmanaged<CFError>?
        guard let secPrivateKey = SecKeyCreateWithData(privateKeyData as CFData, keyAttributes as CFDictionary, &error) else {
            print("SecKeyCreateWithData error: \(String(describing: error))")
            throw QUICServerIdentityCreationError.keychainWriteFailed(error?.takeRetainedValue().asOSStatus() ?? errSecInternalError)
        }
        
        let keyAddQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: args.identityLabel,
            kSecAttrApplicationLabel as String: applicationLabel, // <--- 여기가 핵심 연결 고리!
            kSecAttrIsPermanent as String: true, // 키체인 저장 여부
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueRef as String: secPrivateKey
        ]
        
        let keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        
        guard keyStatus == errSecSuccess else {
            // best-effort cleanup of generated certificate on failure
            let certDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: args.identityLabel
            ]
            SecItemDelete(certDeleteQuery as CFDictionary)
            
            if keyStatus == errSecDuplicateItem {
                throw QUICServerIdentityCreationError.identityAlreadyExists
            }
            throw QUICServerIdentityCreationError.keychainWriteFailed(keyStatus)
        }
        
        let trustSettings: [String: Any] = [
            kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue
        ]
        
        // 3. 신뢰 설정 적용
        // domain: .user (현재 사용자), .admin (관리자-root권한 필요)
        // 이 함수가 호출되면 OS가 사용자에게 비밀번호를 묻는 창을 띄웁니다.
        let trustStatus = SecTrustSettingsSetTrustSettings(
            secCertificate,
            .user,
            trustSettings as CFTypeRef
        )
        
        // 4. 결과 확인
        if trustStatus != errSecSuccess {
            // best-effort cleanup of generated certificate and key on failure
            let certDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: args.identityLabel
            ]
            SecItemDelete(certDeleteQuery as CFDictionary)
            deletePrivateKey(label: args.identityLabel)
            
            // throw QUICServerIdentityCreationError.trustSettingsFailed(status)
            throw QUICServerIdentityCreationError.notImplemented
        }
        
        
        guard let identity = SecIdentityCreate(nil, secCertificate, secPrivateKey) else {
             throw QUICServerIdentityCreationError.identityCreationFailed
        }
        
        // identity already in keychain (via permanent key); return wrapper
        return Self(args.identityLabel)
    }
    
    public func getServerIdentity() async throws -> sec_identity_t {
        let certificateQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: self.identityLabel,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true
        ]
        
        var certificate: CFTypeRef?
        let certificateStatus = SecItemCopyMatching(certificateQuery as CFDictionary, &certificate)
        
        guard certificateStatus != errSecItemNotFound else {
            throw QUICServerIdentityCreationError.identityNotFound
        }
        guard certificateStatus == errSecSuccess, let certificate else {
            throw QUICServerIdentityCreationError.keychainLookupFailed(certificateStatus)
        }
        guard CFGetTypeID(certificate) == SecCertificateGetTypeID() else {
            throw QUICServerIdentityCreationError.keychainLookupFailed(errSecParam)
        }
        
        var identity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(nil, certificate as! SecCertificate, &identity)
        guard identityStatus == errSecSuccess, let identity else {
            if identityStatus == errSecItemNotFound {
                throw QUICServerIdentityCreationError.identityNotFound
            }
            throw QUICServerIdentityCreationError.keychainLookupFailed(identityStatus)
        }
        
        return unsafeBitCast(identity, to: sec_identity_t.self)
    }
    
    public func deleteIdentity() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: self.identityLabel
        ]
        SecItemDelete(query as CFDictionary)
        
        // 개인키도 삭제
        Self.deletePrivateKey(label: self.identityLabel)
    }
    
    private static func identityExists(label: String) -> Bool {
        // kSecClassIdentity 검색 시 라벨이 무시되어 임의의 다른 Identity가 매칭될 수 있으므로,
        // 인증서/개인키 수준에서 라벨 충돌을 확인한다.
        let certificateQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true
        ]
        
        var certificate: CFTypeRef?
        let certificateStatus = SecItemCopyMatching(certificateQuery as CFDictionary, &certificate)
        if certificateStatus == errSecSuccess {
            return true
        }
        
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, nil)
        return keyStatus == errSecSuccess
    }
    
    private static func deletePrivateKey(label: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: label
        ]
        SecItemDelete(query as CFDictionary)
    }
}
