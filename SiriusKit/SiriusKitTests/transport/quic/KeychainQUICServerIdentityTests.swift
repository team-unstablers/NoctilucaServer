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
    @Test
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
