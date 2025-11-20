//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

public class ClientSession {
    let transport: ClientTransport
    
    private(set) var mainChannel: MainChannel?
    // channel manager 필요할 것 같음
    
    init(transport: ClientTransport) {
        self.transport = transport
        self.transport.delegate = self
    }
    
    func openChannel(for feature: SiriusFeature, identifier: ...) async throws -> Channel {
        
    }
}

extension ClientSession: ClientTransportDelegate {
    func clientTransportDidOpenStream(_ transport: ClientTransport, stream: Stream) {
        if mainChannel == nil {
            // 첫번째 스트림은 반드시 메인 채널로 사용한다
            let channel = MainChannel(stream: stream)
            self.mainChannel = channel
            
            return
        }
        
        // 그럼 나머지는?
        
    }
    
    func clientTransportDidCloseStream(_ transport: ClientTransport, stream: Stream) {
        //
    }
    
    func clientTransportDidClose(_ transport: ClientTransport, error: (any Error)?) {
    }
}
