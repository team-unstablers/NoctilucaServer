//
//  NOCSiriusServerApplication.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import SiriusKit

enum NoctilucaServerState {
    case initial
    case ready(server: SiriusServer)
}


class NoctilucaServer {
    var state: NoctilucaServerState = .initial
    
    let featureProvider = NoctilucaFeatureProvider()
    
    init() {
    }
    
    func something() throws {
        let result = try SiriusServerBuilder()
            .useFeatureProvider(featureProvider)
            .useTransportProtocol(.quic(port: 12345, identitySource: .keychain(label: "pl.unstabler.")))
            .withExtraConfiguration("someValue", forKey: "someKey")
            .build()
        
        
        let server = try result.get()
        self.state = .ready(server: server)
    }
}


extension NoctilucaServer: SiriusServerDelegate {
    func siriusServerDidStart(_ server: SiriusKit.SiriusServer) {
        <#code#>
    }
    
    func siriusServerDidStop(_ server: SiriusKit.SiriusServer) {
        <#code#>
    }
    
    func siriusServerDidAcceptClientSession(_ server: SiriusKit.SiriusServer, session: SiriusKit.ClientSession) {
        <#code#>
    }
    
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusKit.SiriusServer, error: any Error) {
        <#code#>
    }
}
