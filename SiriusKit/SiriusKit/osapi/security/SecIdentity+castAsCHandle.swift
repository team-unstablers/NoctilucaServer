//
//  SecIdentity+cast.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

extension SecIdentity {
    func asCHandle() -> sec_identity_t {
        let handle = sec_identity_create(self)
        
        guard handle != nil else {
            fatalError("FIXME: handle != nil을 보장하던가 그렇지 않던가 하십시오")
        }
        
        return handle!
    }
}
