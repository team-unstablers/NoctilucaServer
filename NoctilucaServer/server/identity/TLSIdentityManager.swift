//
//  TLSIdentityManager.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/12/26.
//

import Foundation
import Security
import SiriusKit

enum ServerIdentitySource: Equatable, Hashable, Codable {
    case keychain(label: String)
    case pemFile(certFilePath: String, keyFilePath: String)
}

actor ServerIdentityManager {
    // macOSエンジニアあるある：すぐsingletonにしたがる
    public static let shared = ServerIdentityManager()
    
    init() {
    }
    
    /// 주어진 소스로부터 아이덴티티를 로드합니다.
    func load(source: ServerIdentitySource) async throws -> QUICServerIdentity {
        switch source {
        case .keychain(let label):
            let identity = KeychainQUICServerIdentity(label)
            try await identity.checkExistence()
            
            return identity
        case .pemFile(let certFilePath, let keyFilePath):
            return PEMFileQUICServerIdentity(using: certFilePath, key: keyFilePath)
        }
    }
}
