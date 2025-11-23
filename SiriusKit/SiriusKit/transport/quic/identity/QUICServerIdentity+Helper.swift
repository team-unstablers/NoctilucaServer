//
//  QUICServerIdentity+Helper.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//


public enum QUICServerIdentitySource {
    case keychain(label: String)
    case certFile(pemPath: String, keyPath: String)
}

extension QUICServerIdentity {
    static func create(from source: QUICServerIdentitySource) -> QUICServerIdentity {
        switch source {
        case .keychain(let label):
            return KeychainQUICServerIdentity(label)
        case .certFile(let pemPath, let keyPath):
            return PEMFileQUICServerIdentity(using: pemPath, key: keyPath)
        }
    }
}
