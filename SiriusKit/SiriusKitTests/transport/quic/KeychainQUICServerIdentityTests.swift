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
        let commonName = "pl.unstabler.sirius.SiriusKitTests.QUICServerIdentityTest.\(UUID().uuidString)"
        
        let args = QUICServerIdentityCreationArgs(
            identityLabel: commonName,
            commonName: commonName,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        let identity = try KeychainQUICServerIdentity.createSelfSignedIdentity(args: args)
        
        #expect(try await identity.sanityCheck())
        
        // identity.deleteIdentity()
    }
}
