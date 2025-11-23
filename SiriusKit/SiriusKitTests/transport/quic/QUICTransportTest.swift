//
//  QUICTest.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Testing

import Network

@testable import SiriusKit

/// QUIC 트랜스포트 관련한 클래스를 종합적으로 테스트합니다.
@Suite(.disabled(if: TestConfig.isUnattended))
final class QUICTransportTest {
    private let identifier: UUID
    private let port: NWEndpoint.Port
    
    private let serverIdentity: QUICServerIdentity
    
    init() async throws {
        self.identifier = UUID()
        self.port = NWEndpoint.Port(integerLiteral: 15495)
        
        let commonName = "pl.unstabler.sirius.SiriusKitTests.QUICtest.\(identifier.uuidString)"

        let identityArgs = QUICServerIdentityCreationArgs(
            identityLabel: commonName,
            commonName: commonName,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        self.serverIdentity = try InMemoryQUICServerIdentity.createSelfSignedIdentity(args: identityArgs)
        
        // ASSERTION: 호스트 자신이 신뢰 가능한 인증서를 사용해야만 함
        let sanityCheckResult = try await self.serverIdentity.sanityCheck()
        assert(sanityCheckResult, "this test requires a trustable server identity")
    }
    
    deinit {
        
    }
    
    @Test("QUIC 프로토콜의 서버가 정상적으로 기동되는가")
    func serverStartsSuccessfully() async throws {
        let server = QUICServerTransport(port: self.port, using: self.serverIdentity)
        try await server.startup()
        
        defer {
            Task {
                do {
                    try await server.shutdown()
                } catch {
                    print("WARN: Failed to shutdown QUIC server transport: \(error)")
                }
            }
        }
        
        try await Task.sleep(for: .seconds(2))
        
        // test
        #expect(true)
    }
    
    
}
