//
//  AuthMethod+None.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//


import Foundation

import NoctilucaPluginKit

extension AuthMethod {
#if DEBUG
    /// 인증을 수행하지 않는다. (allow all)
    static let null = AuthMethod(rawValue: "app.noctiluca.server.auth.dev.null")
#endif
    
    static let simplePassword = AuthMethod(rawValue: "app.noctiluca.server.auth.simple-password")
}


