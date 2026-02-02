//
//  NWConnection+QUIC.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Network

extension NWConnection {
    var quicMetadata: NWProtocolQUIC.Metadata? {
        return self.metadata(definition: NWProtocolQUIC.definition) as? NWProtocolQUIC.Metadata
    }

    var quicStreamIdentifier: UInt64? {
        return quicMetadata?.streamIdentifier
    }
}
