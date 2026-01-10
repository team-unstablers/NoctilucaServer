//
//  TLSIdentity+load.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation
import Security
import SiriusKit

extension TLSIdentity {
    func load() -> QUICServerIdentity {
        switch self {
        case .keychain(let identifier):
            return KeychainQUICServerIdentity(identifier)
        case .pemFile(let certFilePath, let keyFilePath):
            return PEMFileQUICServerIdentity(using: certFilePath, key: keyFilePath)
        }
    }
    
    var identitySource: QUICServerIdentitySource {
        switch self {
        case .keychain(let identifier):
            return .keychain(label: identifier)
        case .pemFile(let certFilePath, let keyFilePath):
            return .certFile(pemPath: certFilePath, keyPath: keyFilePath)
        }
    }
    
    func secCertificate() async throws -> SecCertificate {
        let quicIdentity = self.load()
        return try await quicIdentity.secCertificate()
    }
    
    func identityInfo() async throws -> QUICServerIdentityInfo {
        let quicIdentity = self.load()
        return try await quicIdentity.identityInfo()
    }
}
