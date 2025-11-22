<section id="project-info">

# SiriusKit 

SiriusKit은 macOS용 원격 제어 소프트웨어 'Noctiluca'의 핵심 라이브러리입니다. 

이 라이브러리는 Noctilcua에서 사용하는 'Sirius' 프로토콜을 구현하며, Sirius 프로토콜을 만족하는 '서버 역할의 애플리케이션'을 작성할 수 있도록 돕습니다.

# TECHNOLOGIES USED

- Swift
- Google Protobuf 3
- QUIC (via Network.framework)

# SYNOPSIS (draft)

```swift
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
```

## Updates
- `channel/messages` 디렉터리에 msgdef v1 전반(핸드셰이크, 세션 인증, 채널 제어, HIDIO, 프로젝션/윈도우, 프로젝션 데이터, 클립보드)의 Swift 래퍼와 opcode 매핑이 추가되었습니다. SwiftProtobuf로 생성된 코드와 상호 변환할 수 있는 타입들이 포함되어 있습니다.

</section>

<section id="agent-rules">

# AGENT RULES

- 작업을 진행할 때 확실하지 않거나 궁금한 점이 있으면, 되도록 **추측하지 말고 사용자에게 질문**해서 명확히 하는 것을 우선해 주세요.
- 사용자가 한국어 화자인 만큼, Plan 모드에서는 반드시 한국어로 된 플랜을 제시해 주세요.
- 프로젝트에 대한 중요한 정보나 커다란 변경 사항이 있을 때는, `AGENTS.md`를 수정하여 프로젝트에 대한 최신 정보를 반영해 주세요.

## COMMIT CONVENTIONS

- 만약 git commit을 작성할 때는 기존 커밋 컨벤션을 따르는 것을 우선하고, 당신 자신을 Co-author로 추가하지 말아주세요.
- 커밋 컨벤션은 다음과 같습니다.

```
[scope]: [subject]
```

- [scope]: 변경 사항의 범위를 나타내는 짧은 단어 (예: core, ui, docs 등)
- [subject]: 변경 사항을 간결하게 설명하는 문장 (명령문 형태)

### EXAMPLES
  - `transport/quic: QUIC 연결 재시도 로직 추가`
  - `msgdef/v1/channels: 채널 메시지 정의 업데이트`
  - `docs(README): README 파일에 설치 가이드 추가`
  - `test(transport/quic): QUIC 전송 테스트 케이스 작성`

</section>
