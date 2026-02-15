//
//  SREndpoint+MsQuic.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/15/26.
//

import MsQuic
import SwiftMsQuicHelper

package extension SREndpoint {
    init(msQuicAddress: QuicAddress) {
        let port = msQuicAddress.port

        switch msQuicAddress.family {
        case .ipv4:
            let raw = UInt32(bigEndian: msQuicAddress.raw.Ipv4.sin_addr.s_addr)
            self.init(address: .IPv4(raw), port: port)

        case .ipv6:
            let (high, low) = Self.in6AddrToHighLow(msQuicAddress.raw.Ipv6.sin6_addr)
            let scopeId = msQuicAddress.raw.Ipv6.sin6_scope_id
            self.init(address: .IPv6(high: high, low: low, scopeId: scopeId), port: port)

        case .unspecified:
            self.init(address: .IPv4(0), port: port)
        }
    }
}
