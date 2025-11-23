//
//  PEMFileQUICServerIdentityTests.swift
//  SiriusKitTests
//
//  Created by Codex on 2024-06-XX.
//

import Foundation
import Testing
@testable import SiriusKit

struct PEMFileQUICServerIdentityTests {
    @Test
    func createsCertificateAndKeyFiles() throws {
        let basePath = temporaryBasePath()
        let args = QUICServerIdentityCreationArgs(
            identityLabel: basePath,
            commonName: "Test Server",
            organizationName: "Noctiluca",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        _ = try PEMFileQUICServerIdentity.createSelfSignedIdentity(args: args)
        
        #expect(FileManager.default.fileExists(atPath: basePath + ".pem"))
        #expect(FileManager.default.fileExists(atPath: basePath + ".key"))
        
        try? FileManager.default.removeItem(atPath: basePath + ".pem")
        try? FileManager.default.removeItem(atPath: basePath + ".key")
    }
    
    @Test
    func loadsAndPassesSanityCheck() async throws {
        let basePath = temporaryBasePath()
        let args = QUICServerIdentityCreationArgs(
            identityLabel: basePath,
            commonName: "Test Server",
            organizationName: "Noctiluca",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        let identity = try PEMFileQUICServerIdentity.createSelfSignedIdentity(args: args)
        
        _ = try await identity.getServerIdentity()
        let passed = try await identity.sanityCheck(strict: false)
        #expect(passed)
        
        try? FileManager.default.removeItem(atPath: basePath + ".pem")
        try? FileManager.default.removeItem(atPath: basePath + ".key")
    }
    
    // MARK: - Helpers
    private func temporaryBasePath() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        return tempDir.appendingPathComponent("siriuskit-\(id)").path
    }
}
