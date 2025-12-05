//
//  AuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//


import Foundation
import SiriusKit

enum AuthError: LocalizedError {
    case unknownError

    case unsupportedMethod
    case invalidPayload
    case authenticationFailed(Error?)
}

protocol AuthPlugin: AnyObject {
    static var id: String { get }
    static var name: String { get }
    static var description: String { get }
    static var author: String { get }
    static var license: String { get }

    static var version: UInt32 { get }
    static var displayVersion: String { get }
    
    static var supportedMethods: Set<AuthMethod> { get }

    init()
    
    func initialize() async throws
    func deinitialize() throws

    func allow(_ entry: AllowedAuthMethod) async throws
    func deny(_ entry: AllowedAuthMethod) async throws
    
    func authenticate(using method: AuthMethod, payload: borrowing Data) async -> Result<uid_t, AuthError>
}
