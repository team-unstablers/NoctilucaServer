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
    
    @Test("KeychainQUICServerIdentity가 키체인에 올바르게 항목을 생성할 수 있는가", .disabled(if: skipTest))
    func createsKeychainEntry() async throws {
        let keychain = SRKeychain.shared
        
        let commonName = "pl.unstabler.sirius.SiriusKitTests.QUICServerIdentityTest.\(UUID().uuidString)"
        
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
            try? keychain.deleteItem(by: commonName, clazz: .privateKey).get()
        }
        
        let identity = try KeychainQUICServerIdentity.createSelfSignedIdentity(args: args)
        
        #expect(try await identity.sanityCheck())
    }
}
