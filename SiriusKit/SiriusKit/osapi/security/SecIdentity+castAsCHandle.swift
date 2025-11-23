//
//  SecIdentity+cast.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

extension SecIdentity {
    func castAsCHandle() -> sec_identity_t {
        return unsafeBitCast(self, to: sec_identity_t.self)
    }
}
