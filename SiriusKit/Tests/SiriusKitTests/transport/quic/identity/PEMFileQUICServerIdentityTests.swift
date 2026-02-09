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
    
    /// 자가 서명 인증서를 trust 처리하는 과정에서 사용자 인증 다이얼로그가 뜨므로 테스트를 건너뛸 수 있도록 합니다
    static let skipTest = true

    @Test(".pem / .key 페어의 인증서를 생성할 수 있는가")
    func createsCertificate() async throws {
        let basePath = temporaryBasePath()
        
        let identifier = UUID().uuidString
        let commonName = "so.libsirius.tests.QUICServerIdentityTest.\(identifier)"
        
        let args = QUICServerIdentityCreationArgs(
            identityLabel: basePath,
            commonName: commonName,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        let identity = try PEMFileQUICServerIdentity.createSelfSignedIdentity(args: args)
        
        #expect(FileManager.default.fileExists(atPath: basePath + ".pem"))
        #expect(FileManager.default.fileExists(atPath: basePath + ".key"))
        
        #expect(try await identity.sanityCheck())
    }
    
    // MARK: - Helpers
    private func temporaryBasePath() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        return tempDir.appendingPathComponent("siriuskit-\(id)").path
    }
}
