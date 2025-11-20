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

class Concept {
    var client: ClientSession!
    
    func onClientConnect() async throws {
        // HIDIO를 설정한다 -> 키보드, 마우스 입력을 받을 수 있다
        let hidioChannel = try await self.client.openChannel(for: .hidio, identifier: UUID())
        hidioChannel.delegate = self
        
        // 프로젝션 채널을 연다. -> 화면 전송 제어용
        let projectionChannel = try await self.client.openChannel(for: .projection, identifier: UUID())
        
        projectionChannel.delegate = self
    }
}

extension Concept: HIDIOChannelDelegate {
    func hidioChannelDidReceiveKeyEvent(_ channel: HIDIOChannel, event: KeyEvent) {
        self.handleKeyEvent(event)
    }
    
    func hidioChannelDidReceiveMouseMoveEvent(_ channel: HIDIOChannel, event: MouseMoveEvent) {
        self.handleMouseMoveEvent(event)
    }
}

extension Concept: ProjectionChannelDelegate {
    func projectionChannelDidReceiveProjectionRequest(_ channel: ProjectionChannel, request: ProjectionRequest) {
        guard windowManager.windowExists(request.windowId), ... else {
            return
        }
        
        let projector = SessionProjector()
        projector.configure(codec: request.codec, ...)
        
        let channelIdentifier = UUID()
        let projectionDataChannel = try await channel.openChannel(for: .projectionData, identifier: channelIdentifier)
        projector.startProjection(to: projectionDataChannel, windowId: request.windowId)
        
        let event = ProjectionStartedEvent(
            channelIdentifier: channelIdentifier,
            codec: projector.codec,
            ...
        )
        
        channel.sendProjectionStartedEvent(event)
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
