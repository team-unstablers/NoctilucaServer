//
//  Channel+getClientSession.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKitCore
public extension Channel {
    var clientSession: SiriusClient? {
        guard let session = self.handle.asImpl.session as? SiriusClient else {
            return nil
        }

        return session
    }
}
