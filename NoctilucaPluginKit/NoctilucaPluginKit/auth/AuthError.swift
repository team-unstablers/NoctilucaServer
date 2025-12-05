//
//  AuthError.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

public enum AuthError: LocalizedError {
    case unknownError

    case unsupportedMethod
    case invalidPayload
    case authenticationFailed(Error?)
}
