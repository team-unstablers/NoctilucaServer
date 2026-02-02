//
//  Channel+getClientSession.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKitCore
public extension Channel {
    var clientSession: ClientSession? {
        guard let session = self.session as? ClientSession else {
            return nil
        }

        return session
    }
}
