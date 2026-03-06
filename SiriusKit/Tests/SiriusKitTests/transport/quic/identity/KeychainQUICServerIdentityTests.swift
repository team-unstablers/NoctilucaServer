//
//  PEMFileQUICServerIdentityTests.swift
//  SiriusKitTests
//
//  Created by Codex on 2024-06-XX.
//

import Foundation
import Testing
@testable import SiriusKit

struct KeychainQUICServerIdentityTests {
    
    /// 자가 서명 인증서를 trust 처리하는 과정에서 사용자 인증 다이얼로그가 뜨므로 테스트를 건너뛸 수 있도록 합니다
    static let skipTest = true
    static let runManualChainFixtureTest: Bool = ProcessInfo.processInfo
        .environment["SIRIUSKIT_TEST_MANUAL_KEYCHAIN_CHAIN"] == "1"
    static let manualLeafLabel: String = ProcessInfo.processInfo
        .environment["SIRIUSKIT_TEST_KEYCHAIN_LEAF_LABEL"] ?? "전자 병아리 #3156"
    static let manualIntermediateCommonName: String = ProcessInfo.processInfo
        .environment["SIRIUSKIT_TEST_KEYCHAIN_INTERMEDIATE_CN"] ?? "전자 병아리 주식회사 Intermediate CA"
    static let manualRootCommonName: String = ProcessInfo.processInfo
        .environment["SIRIUSKIT_TEST_KEYCHAIN_ROOT_CN"] ?? "전자 병아리 주식회사 Root CA"
    
    @Test("KeychainQUICServerIdentity가 키체인에 올바르게 항목을 생성할 수 있는가", .disabled(if: skipTest))
    func createsKeychainEntry() async throws {
        let keychain = SRKeychain.shared
        
        let commonName = "so.libsirius.SiriusKit.tests.QUICServerIdentityTest.\(UUID().uuidString)"
        
        let args = QUICServerIdentityCreationArgs(
            identityLabel: commonName,
            commonName: commonName,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        defer {
            try? keychain.deleteItem(by: commonName, clazz: .certificate).get()
            try? keychain.deleteItem(by: commonName, clazz: .privateKey, extras: [
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
            ]).get()
        }
        
        let identity = try KeychainQUICServerIdentity.createSelfSignedIdentity(args: args)
        
        #expect(try await identity.sanityCheck())
    }

    @Test(
        "수동 체인 픽스처(leaf/intermediate/root)에서 self-signed root를 포함한 체인을 반환하는가",
        .disabled(if: !runManualChainFixtureTest || TestConfig.isUnattended)
    )
    func returnsChainIncludingSelfSignedRootForManualKeychainFixture() async throws {
        let identity = KeychainQUICServerIdentity(Self.manualLeafLabel)

        let leaf = try await identity.secCertificate()
        let leafCommonName = leaf.extractCommonName()
        #expect(leafCommonName == Self.manualLeafLabel)

        let chain = try await identity.getCertificateChain()
        let chainCommonNames = Set(chain.compactMap { $0.extractCommonName() })

        #expect(chainCommonNames.contains(Self.manualIntermediateCommonName))
        #expect(chainCommonNames.contains(Self.manualRootCommonName))
    }
}
