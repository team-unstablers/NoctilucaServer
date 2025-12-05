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
    static let none = AuthMethod(rawValue: "pl.unstabler.noctiluca.NoctilucaServer.auth.dev.none")
#endif
    
    static let simplePassword = AuthMethod(rawValue: "pl.unstabler.noctiluca.NoctilucaServer.auth.simplePassword")
}


