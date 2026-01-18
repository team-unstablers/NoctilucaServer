//
//  ClientAuthPluginV1.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

enum ClientAuthPluginError: LocalizedError {
    case unsupportedEntry
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .unsupportedEntry:
            return "Unsupported auth entry"
        case .invalidPayload:
            return "Invalid auth payload"
        }
    }
}

protocol ClientAuthPluginV1: AnyObject {
    static var id: String { get }
    static var name: String { get }
    static var description: String { get }

    static var supportedMethods: Set<ClientAuthMethod> { get }

    init()

    func payload(for entry: ClientAuthEntry, nonce: Data) throws -> Data
}
