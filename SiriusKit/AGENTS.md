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
- `logging/SiriusLogger`가 추가되어 OSLog 또는 콘솔 대상으로 로깅을 보낼 수 있습니다. `SiriusLogVerbosity`/`configure`로 전역 최소 레벨과 대상 팩토리를 조정할 수 있습니다.
- `channel/messages` 디렉터리에 msgdef v1 전반(핸드셰이크, 세션 인증, 채널 제어, HIDIO, 프로젝션/윈도우, 프로젝션 데이터, 클립보드)의 Swift 래퍼와 opcode 매핑이 추가되었습니다. SwiftProtobuf로 생성된 코드와 상호 변환할 수 있는 타입들이 포함되어 있습니다.
- 트랜스포트 레이어가 역할별 디렉터리로 분리되었습니다. 서버 역할(`transport/server/**`)은 `ServerRoleRootTransport`, `ServerRoleClientTransport`, `ServerRoleQUICRootTransport`/`ServerRoleQUICClientTransport`로 네이밍을 명확히 했고, 공통 ALPN 정의는 `transport/quic/QUICConstants.swift`에 위치합니다.
- 클라이언트 역할 트랜스포트 뼈대가 `transport/client/**`에 추가되었습니다. `ClientRoleTransport`/`ClientRoleQUICTransport`가 서버 인증서 검증(TrustDecision 콜백)과 메인 채널 스트림 오픈 이벤트를 델리게이트로 노출합니다.
- 프로젝션 채널의 `CodecOption`/`CodecOptionsParser` 관련 타입을 SiriusKit로 옮기고 `public`으로 공개했습니다. 서버/클라이언트 공용으로 옵션 파싱과 키/값 상수를 재사용할 수 있습니다.

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
<section id="about-sirius-protocol">
# NAME

Sirius - macOS용 원격 제어 소프트웨어 'Noctiluca'의 기반 프로토콜

Sirius는 서버와 클라이언트 사이에서 원격 제어 세션을 설정하고 관리하기 위한
애플리케이션 레벨 프로토콜입니다.  
핸드셰이크, 인증, 채널 생성과 같은 공통 절차를 담당하며,
화면 전송·입력 전송 등 개별 기능은 별도의 채널로 분리하여 처리합니다.

# STRUCTURE OVERVIEW

Sirius 프로토콜은 서버-클라이언트 모델을 기반으로 합니다.
아래 다이어그램은 macOS 상의 서버 애플리케이션, 트랜스포트 레이어, 클라이언트 애플리케이션 간의
레이어 구조와 그 위에서 동작하는 채널과 스트림의 관계를 간략히 나타냅니다.

```
+--------------------+
|    Projects GUI    |
|       Session      |                     +-----------------+
+--------------------+---------------------+    Redirects    |
|  ScreenCaptureKit  | User Authentication |    HID Event    |
+--------------------+---------------------+-----------------+-----------+
|    VideoToolbox    |       PAM API       | Cocoa Event Tap |    ...    |
+------------------------------------------------------------------------+
|                           Server Application                           | ------- 여기서부턴 Sirius 프로토콜의 영역 바깥 (각 서버가 직접 구현) -------
+--------------------+------------------+--------------------+-----------+
|    Main Channel    |    Channel #N    |    Channel #N+1    |    ...    |
+--------------------+------------------+--------------------+-----------+
|     Stream  #1     |    Stream  #N    |    Stream  #N+1    |    ...    |
+--------------------+------------------+--------------------+-----------+
|                      Transport Layer (e.g., QUIC)                      |
+------------------------------------------------------------------------+
                                   ||
                                   ||
                                   ||
+------------------------------------------------------------------------+
|                      Transport Layer (e.g., QUIC)                      |
+--------------------+------------------+--------------------+-----------+
|     Stream  #1     |    Stream  #N    |    Stream  #N+1    |    ...    |
+--------------------+------------------+--------------------+-----------+
|    Main Channel    |    Channel #N    |    Channel #N+1    |    ...    |
+--------------------+------------------+--------------------+-----------+
|                           Client Application                           |
+------------------------------------------------------------------------+
```

## MULTI-CHANNEL ARCHITECTURE

Sirius는 하나의 트랜스포트 커넥션 위에서 여러 개의 기능을 동시에 다루기 위해
채널(channel)이라는 개념을 사용합니다.

- 채널(channel)은 Sirius 프로토콜 레벨에서 정의되는 **논리적인 통신 단위**입니다.
- 각 채널은 트랜스포트 레이어(예: QUIC)의 스트림(stream)에 **1:1로 매핑**됩니다.
- 하나의 서버-클라이언트 커넥션에는 다수의 스트림과 채널이 동시에 존재할 수 있습니다.

각 채널은 특정 기능(feature)을 담당하며 서로 독립적으로 동작합니다.

- 예를 들어, 다음과 같은 기능들이 별도 채널로 구현될 수 있습니다.
  - HIDIO: 키보드·마우스 등 입력 이벤트 전송
  - Projection: 화면 전송 제어
  - ProjectionData: 인코딩된 비디오 프레임 전송
- 하나의 기능이 여러 채널로 나뉘어 구현될 수도 있습니다.
  - 예: 화면 전송 기능을 제어 채널과 데이터 채널로 분리

Sirius에서 사용되는 트랜스포트 레이어는 멀티플렉싱을 지원하는 프로토콜 사용을 권장합니다.

- 예: QUIC
- 멀티플렉싱을 지원하지 않는 프로토콜 위에서도, 애플리케이션 레벨에서 스트림을 흉내 내는 방식으로
  구현은 가능하지만 이는 권장되지 않습니다.

### Channel Lifecycle 개요

- 서버와 클라이언트는 **필요할 때마다 채널을 생성(open)하고 종료(close)할 수 있습니다.**
- 채널은 서버·클라이언트 어느 쪽에서든 시작할 수 있으며,
  채널 시작 시에는 반드시 **해당 채널이 어떤 기능(feature)을 위한 것인지**를 상대에게 알려야 합니다.
- 채널이 닫히면 해당 채널과 연결된 스트림도 함께 종료됩니다.

자세한 메시지와 상태 전이는 `msgdef/v1/channels.proto`에 정의되어 있습니다.

### MAIN CHANNEL

모든 Sirius 커넥션에는 반드시 하나의 **메인 채널(main channel)**이 존재해야 합니다.

- 트랜스포트 커넥션이 수립된 직후, 가장 먼저 생성된 스트림/채널을 메인 채널로 간주합니다.
- 메인 채널은 세션 전반에 걸친 공통 제어 흐름을 담당합니다.

메인 채널은 주로 다음과 같은 역할을 수행합니다.

- 프로토콜 핸드셰이크 수행
  - `ClientHello`, `ServerHello` 메시지 교환
- 사용자 인증(Authentication) 처리
  - `AuthChallenge`, `AuthRequest`, `AuthResponse`
- `ServerNotice`와 같이 세션 전체에 영향을 주는 전역 알림 전송

특수한 사유(예: 프로토콜 버전 불일치, 치명적 오류 등)로 인해 메인 채널이 종료되면,
일반적으로 해당 트랜스포트 커넥션도 함께 종료됩니다.

# CHANNEL MESSAGES

Sirius 프로토콜에서 사용되는 모든 메시지는 **Protocol Buffers v3**로 정의합니다.

- 공통 메시지 및 메인 채널용 메시지: `msgdef/general.proto`
- 세션 관리 및 인증 관련 메시지: `msgdef/v1/session.proto`
- 채널 시작/종료 관련 메시지: `msgdef/v1/channels.proto`
- 기능별 채널 메시지: `msgdef/v1/channels/**.proto`
  - 예: HIDIO, Projection, Window Management 등

각 메시지에는 opcode가 할당되며, 프레이밍 규칙은 아래 **OPCODES** 및 **FRAME STRUCTURE** 섹션에
정의합니다.

## OPCODES

모든 Sirius 프로토콜 메시지는 2바이트 길이의 opcode를 갖습니다.

- opcode는 메시지의 종류를 나타내는 고유 식별자입니다.
- opcode는 Big-Endian 형식으로 인코딩됩니다.

### GLOBAL OPCODES vs FEATURE CHANNEL OPCODES

opcode 공간은 두 가지 용도로 나누어 사용합니다.

- `0x0000` ~ `0x7FFF`: **Global opcode**
  - 메인 채널을 포함한 **모든 채널에서 공통으로 사용되는 메시지**에 할당됩니다.
  - 예:
    - 핸드셰이크 메시지 (`ClientHello`, `ServerHello`)
    - 인증 메시지 (`AuthChallenge`, `AuthRequest`, `AuthResponse`)
    - 채널 관리 메시지 (`ChannelStartRequest`, `ChannelStartResponse`, `ChannelCloseRequest`)
- `0x8000` ~ `0xFFFF`: **Feature channel opcode**
  - 각 기능(feature)에서 **채널별로 정의하는 메시지**에 사용됩니다.
  - 예:
    - HIDIO 채널의 입력 이벤트 메시지
    - Projection 채널의 프로젝션 요청/이벤트 메시지
  - 동일한 숫자 값의 opcode라도, 채널/기능에 따라 다른 메시지를 의미할 수 있습니다.

각 기능은 자신이 사용하는 feature channel opcode의 범위를 책임지고 관리해야 합니다.

## FRAME STRUCTURE

모든 Sirius 메시지는 다음과 같은 고정된 프레이밍 구조를 사용합니다.

```
+----------------+----------------+----------------+
|    Opcode      |  Payload Len   |    Payload     |
|   (2 bytes)    |   (4 bytes)    |  (variable)    |
+----------------+----------------+----------------+
```

- **Opcode (2 bytes)**  
  메시지 타입을 나타내는 고유 식별자입니다. Big-Endian 형식으로 인코딩합니다.

- **Payload Len (4 bytes)**  
  페이로드의 길이를 나타냅니다. Big-Endian 형식의 부호 없는 정수이며,  
  **opcode와 길이 필드를 제외한 Protobuf 직렬화 바이트 수**를 의미합니다.

- **Payload (variable)**  
  Protobuf v3로 직렬화된 실제 메시지 데이터를 포함하는 가변 길이 필드입니다.

# PROTOCOL FLOW

Sirius 프로토콜의 기본적인 세션 수립 흐름은 다음과 같습니다.

1. 트랜스포트 커넥션 수립
2. 메인 채널 생성
3. 프로토콜 핸드셰이크
4. 사용자 인증
5. 기능별 채널 생성 및 사용

아래에서 각 단계를 간략히 설명합니다.

## 1. 커넥션 수립

- 서버와 클라이언트는 QUIC 등 멀티플렉싱을 지원하는 트랜스포트 프로토콜을 사용해
  커넥션을 수립합니다.
- TLS 위에서 동작하는 프로토콜인 경우, 서버 인증서를 검증하여 MITM 공격 등을 방지해야 합니다.

서버 인증서 검증에 대한 권장 사항:

- 서버의 인증서 지문(fingerprint)을 내부적으로 관리하는 **트러스트 리스트**를 사용합니다.
  - 대부분의 Sirius 호스트는 자가 서명(self-signed) 인증서를 사용할 것으로 예상됩니다.
  - OS 차원의 트러스트 스토어만으로는 신뢰 여부를 충분히 표현하기 어렵습니다.
- 트러스트 리스트에 없는 호스트인 경우:
  - 사용자에게 경고 메시지를 표시하고, 연결을 계속 진행할지 여부를 확인하는 UI를 제공하는 것을 권장합니다.
- 트러스트 리스트에 엔트리가 있지만, 저장된 지문과 실제 지문이 다른 경우:
  - "서버가 위장되었을 수 있습니다"와 같은 경고 메시지를 표시하고,
    사용자가 명시적으로 허용하지 않는 한 연결을 거부하는 것이 바람직합니다.
- 사용자가 연결을 허용하지 않기로 선택한 경우:
  - 즉시 트랜스포트 커넥션을 종료합니다.

## 2. 메인 채널 생성

- 커넥션이 수립된 직후, **클라이언트는 메인 채널을 생성**해야 합니다.
- 메인 채널 생성은 트랜스포트 레이어에서 첫 번째 스트림을 여는 방식으로 이루어집니다.
- 사전에 정의된 제한 시간 내에 메인 채널이 생성되지 않으면,
  서버는 커넥션을 타임아웃으로 간주하고 종료할 수 있습니다.

## 3. 핸드셰이크

### 3-1. 클라이언트 핸드셰이크 요청

메인 채널이 준비되면, 클라이언트는 서버에게 `ClientHello` 메시지를 전송합니다.

```swift
mainChannel.send(ClientHello(
    // Sirius V1
    protocolVersion: 0x0100,
    agentName: "Noctiluca Client/1.0"
))
```

`agentName` 필드는 아래 형식을 따르는 것을 권장합니다.

```ebnf
AGENT              = APPLICATION_NAME , "/" , VERSION , [ " " , ADDITIONAL_INFO ] ;

APPLICATION_NAME   = 1*( ALPHA | DIGIT | "-" | "_" ) ;
VERSION            = 1*( ALPHA | DIGIT | "." | "-" ) ;

ADDITIONAL_INFO    = "(" , INFO_ITEM , *( ";" , INFO_ITEM ) , ")" ;
INFO_ITEM          = PLATFORM | LIB_INFO | FLAG ;

PLATFORM           = 1*( ALPHA | DIGIT | "-" | "_" ) ;
LIB_INFO           = LIB_NAME , "/" , VERSION ;
LIB_NAME           = 1*( ALPHA | DIGIT | "-" | "_" ) ;

FLAG               = "+" , 1*( ALPHA | DIGIT | "-" | "_" ) ;
```

예를 들어, 다음과 같은 값을 사용할 수 있습니다.

- `NoctilucaClient/1.0 (macOS 14.0; libsirius/1.2.3; +automated)`
  - macOS 14.0에서 동작하는 Noctiluca Client 버전 1.0. +automated 플래그가 설정되어 있으므로 컴퓨터를 자동화된 스크립트가 제어할 것임을 나타냅니다.

### 3-2. 서버 핸드셰이크 응답

서버는 `ClientHello`를 수신한 뒤, 다음 항목을 검증합니다.

- 지원하지 않는 프로토콜 버전인지 여부
- 너무 오래된(지원 중단된) 프로토콜 버전인지 여부
- 서버 상태가 새 세션을 수락할 수 있을 정도로 여유가 있는지 여부
  - 예: 동시 세션 수 제한, 리소스 부족 등

검증이 끝나면 서버는 `ServerHello` 또는 `ServerNotice`를 전송합니다.

```swift
// 허용 가능한 요청인 경우
mainChannel.send(ServerHello(
    // Sirius V1
    protocolVersion: 0x0100,
    serverName: "Noctiluca Server/1.0",
    supportedFeatures: [ .hidio, .projection, ... ]
))

// 허용 불가능한 요청인 경우
mainChannel.send(ServerNotice(
    severity: .fatal,
    code: .unsupportedProtocolVersion,
    message: "Unsupported protocol version",
    timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
))

mainChannel.close()
transport.close()
```

`supportedFeatures`에는 서버가 제공하는 기능의 식별자가 포함됩니다.
실제 메시지 정의에서는 기능 식별자로 UUID를 사용하며(`msgdef/general.proto` 참고),
애플리케이션 레벨에서는 이를 `.hidio`, `.projection` 등 enum 형태로 래핑하여 사용할 수 있습니다.

## 4. 사용자 인증 (Authentication)

핸드셰이크가 성공적으로 완료되면, 서버는 클라이언트에게 인증을 요구할 수 있습니다.

### 4-1. 인증 방식 제시 (`AuthChallenge`)

서버는 `AuthChallenge` 메시지를 통해 클라이언트가 선택할 수 있는 인증 방식을 제시합니다.

```swift
mainChannel.send(AuthChallenge(
    acceptedMethods: [.password, .sshKey],
    message: "이 컴퓨터는 Acme Corp. 소유입니다. 허가 받지 않은 접근을 금지합니다."
))
```

`acceptedMethods`는 다음과 같은 값들을 포함할 수 있습니다.  
구체적인 enum 정의는 `msgdef/v1/session.proto`를 참고하세요.

- `AUTH_METHOD_NONE`
- `AUTH_METHOD_PASSWORD`
- `AUTH_METHOD_SIMPLE_PASSWORD`
- `AUTH_METHOD_SSH_KEY`

### 4-2. 클라이언트 인증 요청 (`AuthRequest`)

클라이언트는 `acceptedMethods`에서 지원되는 방식 중 하나를 선택하고,
필요한 인증 정보를 `AuthRequest` 메시지로 전송합니다.

```swift
mainChannel.send(AuthRequest(
    method: .password,
    payload: encryptedPayloadData
))
```

- `method`: 선택한 인증 방식
- `payload`: 선택한 방식에 필요한 인증 정보 (예: 사용자 이름·비밀번호, 서명 등)

사용 가능한 인증 방식이 하나도 없다고 판단되는 경우, 클라이언트는 커넥션을 종료해야 합니다.

### 4-3. 서버 측 인증 처리

서버는 `AuthRequest`를 수신한 뒤, 내부 인증 시스템(PAM 등)을 통해 인증을 수행합니다.

```swift
let authRequest: AuthRequest
assert(authRequest.method == .password)

let payload = JSON.parse(authRequest.payload) as AuthPasswordPayload

guard pam.authenticate(payload.username, payload.password) else {
    mainChannel.send(AuthChallenge(
        acceptedMethods: [.password, .sshKey],
        message: "인증에 실패했습니다. 다시 시도해 주세요."
    ))

    maxRetryCount -= 1

    if maxRetryCount <= 0 {
        mainChannel.send(ServerNotice(
            severity: .fatal,
            code: .authenticationFailed,
            message: "Authentication failed",
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        ))

        mainChannel.close()
        transport.close()
    }
    return
}

// 인증 성공
mainChannel.send(AuthResponse(
    sessionId: UUID()
))
```

서버는 정책에 따라 재시도 가능 횟수, 잠금(lock-out) 정책 등을 자유롭게 정의할 수 있습니다.

## 5. 채널 생성 및 기능 사용

인증까지 성공적으로 완료되면, 클라이언트와 서버는 각자 필요한 기능을 사용하기 위해
새로운 채널을 생성할 수 있습니다.

일반적인 권장 패턴은 다음과 같습니다.

- 원격 제어에 **필수적인 기능**에 대한 채널은 클라이언트가 생성한다.
  - 예: HIDIO, Projection
- 서버가 주도적으로 푸시해야 하는 기능이 있는 경우, 서버가 채널을 시작할 수도 있다.

### 채널 생성 예시 (개념 코드)

```swift
class ClientSideSession {
    let transport: Transport

    func openChannel<Ch>(
        for feature: SiriusFeature,
        identifier: UUID,
        args: [String] = []
    ) async throws -> Ch where Ch: SiriusChannel {
        // 새 스트림을 연다.
        let stream = try await transport.openStream()

        // "이 스트림은 어떤 기능(feature)을 위한 채널이다"라고 상대에게 알린다.
        stream.send(ChannelStartRequest(
            featureId: feature.rawValue,
            channelId: identifier,
            args: args
        ))

        let data = try await stream.blockUntilReceive()
        // ... parse ...
        let response = ChannelStartResponse(data: data)

        guard response.success else {
            throw SiriusError.channelStartFailed(code: response.code, message: response.message)
        }

        let channel = Ch(
            stream: stream,
            identifier: identifier
        )

        return channel
    }
}

extension ServerSideSession: TransportDelegate {
    func transportDidOpenStream(_ transport: Transport, stream: Stream) {
        Task {
            let data = try await stream.blockUntilReceive()
            // ... parse ...
            let request = ChannelStartRequest(data: data)

            guard let feature = SiriusFeature(rawValue: request.featureId) else {
                stream.send(ChannelStartResponse(
                    success: false,
                    code: .unknownFeature,
                    message: "Unknown feature ID"
                ))
                stream.close()
                return
            }

            switch feature {
            case .hidio:
                let channel = HIDIOChannel(
                    stream: stream,
                    identifier: request.channelId
                )
                self.registerChannel(channel)

            case .projection:
                let channel = ProjectionChannel(
                    stream: stream,
                    identifier: request.channelId
                )
                self.registerChannel(channel)

            // ...
            default:
                stream.send(ChannelStartResponse(
                    success: false,
                    code: .unsupportedFeature,
                    message: "Unsupported feature"
                ))
                stream.close()
                return
            }

            stream.send(ChannelStartResponse(
                success: true,
                code: 0
            ))
        }
    }
}
```

위 예시는 실제 구현 코드를 그대로 나타내기보다는,
**채널 생성 흐름**을 이해하기 위한 개념 코드입니다.

- 클라이언트:
  - 새 스트림 생성 → `ChannelStartRequest` 전송 → 응답 검증 → 채널 객체 생성
- 서버:
  - 새 스트림에 대한 첫 메시지를 `ChannelStartRequest`로 파싱
  - feature ID를 해석하여 적절한 채널 타입을 생성
  - 성공 여부를 `ChannelStartResponse`로 회신

### High-level 사용 예시

```swift
/// 키보드와 마우스 입력을 전송하기 위한 HIDIO 채널 생성
let hidioChannel = try await session.openChannel(
    for: .hidio,
    identifier: UUID()
)

/// 화면 전송 제어를 위한 Projection 채널 생성
let projectionChannel = try await session.openChannel(
    for: .projection,
    identifier: UUID()
)

/// 화면 전송 데이터를 수신하기 위한 ProjectionData 채널 생성
let projectionDataChannel = try await session.openChannel(
    for: .projectionData,
    identifier: UUID()
)

hidioChannel.moveMouse(x: 100, y: 200)
hidioChannel.keyDown(keyCode: 0x04) // 'A' key down
hidioChannel.keyUp(keyCode: 0x04)   // 'A' key up

let windowList = projectionChannel.requestWindowList(
    filter: [.titleContains("Xcode")]
)

// ...

projectionChannel.requestProjection(
    viewport: .singleWindow(someWindowId),
    preferredCodecs: [
        .h265(
            quality: .auto,
            frameRate: 60.000,
            width: -1,
            height: -1,
            options: "color-format: 'YUV444'; hardware-acceleration: 'auto'; profile: 'high'; level: '4.2';"
        ),
        .h264(
            quality: .high,
            frameRate: 30.000,
            width: 1280,
            height: 720,
            options: "color-format: 'YUV420'; hardware-acceleration: 'auto'; profile: 'main'; level: '4.0';"
        )
    ]
)

// 서버가 ProjectionStarted 이벤트를 보냄과 동시에 'ProjectionData' 채널이 열린다.
// ProjectionData 채널을 통해 H.264 / H.265 인코딩된 화면 데이터가 전송된다.
// ...

projectionDataChannel.onVideoFrameReceived { frame in
    renderVideoFrame(frame)
}
```

위 예시는 라이브러리 사용자 관점에서 **세션 → 채널 → 기능 사용**으로 이어지는
전형적인 Sirius 기반 원격 제어 워크플로를 보여줍니다.

</section>
