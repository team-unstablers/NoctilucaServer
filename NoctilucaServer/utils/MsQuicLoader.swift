//
//  MsQuicHelper.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/4/26.
//

import SwiftMsQuic

import SiriusKit

class MsQuicLoader: @unchecked Sendable {
    static let shared = MsQuicLoader()
    
    private let logger = NoctilucaLogger(category: "MsQuicLoader")
    
    private(set) var success: Bool = false
    
    private init() {
        self.logger.info("ctor(): performing SwiftMsQuicAPI.open()...")
        
        let retval = SwiftMsQuicAPI.open()
        self.success = retval.succeeded
        
        if self.success {
            self.logger.info("ctor(): SwiftMsQuicAPI.open() succeeded")
        } else {
            self.logger.error("ctor(): SwiftMsQuicAPI.open() failed (retval = \(retval.rawValue))")
        }
    }
    
    deinit {
        guard success else {
            return
        }
        
        self.logger.info("deinit: closing SwiftMsQuicAPI. Goodbye! XD")
        SwiftMsQuicAPI.close()
    }
}
