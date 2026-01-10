//
//  TLSIdentity.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation

enum TLSIdentity: Equatable, Hashable, Codable {
    case keychain(identifier: String)
    case pemFile(certFilePath: String, keyFilePath: String)
}
