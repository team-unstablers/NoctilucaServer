//
//  UserActivityAssertion.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/24/26.
//

import IOKit.pwr_mgt

struct UserActivityAssertion: ~Copyable {
    let assertionID: IOPMAssertionID
    
    static func acquire() -> UserActivityAssertion? {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NoctilucaServer User Activity" as CFString,
            &assertionID
        )
        
        guard result == kIOReturnSuccess else {
            return nil
        }
        
        return UserActivityAssertion(assertionID: assertionID)
    }
    
    static func wakeup() {
        var assertionID: IOPMAssertionID = 0
        
        /// 자동으로 macOS에서 release함
        _ = IOPMAssertionDeclareUserActivity(
            "NoctilucaServer User Activity" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }
    
    deinit {
        IOPMAssertionRelease(assertionID)
    }
}
