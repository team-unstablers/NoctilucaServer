//
//  QUICServerIdentity+Helper.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//


public enum QUICServerIdentitySource {
    case keychain(label: String)
    case certFile(pemPath: String, keyPath: String)
    
    func build() -> QUICServerIdentity {
        switch self {
        case .keychain(let label):
            return KeychainQUICServerIdentity(label)
        case .certFile(let pemPath, let keyPath):
            return PEMFileQUICServerIdentity(using: pemPath, key: keyPath)
        }
    }
}
