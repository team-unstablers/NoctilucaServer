<section id="project-info">

# SiriusKit

SiriusKit은 macOS용 원격 제어 소프트웨어 'Noctiluca'의 핵심 라이브러리입니다.
Sirius 프로토콜(세션/채널/메시지/트랜스포트)을 구현하며,
서버 역할/클라이언트 역할 앱이 동일한 코드베이스를 공유할 수 있도록 설계되어 있습니다.

# TECHNOLOGIES USED

- Swift (Concurrency/AsyncStream 포함)
- Network.framework (QUIC, NWConnection/NWConnectionGroup)
- SwiftProtobuf 3 (msgdef 코드 생성)
- CryptoKit + SwiftASN1 + X509(swift-certificates) (서버 인증서 생성)
- Security.framework (Keychain, 인증서/키, 신원 검증)
- OSLog (옵션), 콘솔 로깅
- Atomics (스트림 write backpressure 추적)

# DIRECTORY STRUCTURE (SiriusKit/)

- `SiriusKit/`
  - `client/`:
    - `SiriusClient`, `SiriusClientBuilder`, 델리게이트 정의
  - `server/`:
    - `SiriusServer`, `SiriusServerBuilder`, `ClientSession` (서버가 수락한 연결 단위)
  - `channel/`:
    - `Channel`, `MainChannel`, `ChannelManager`, `ChannelOpenTask`
    - `channel/messages/`: `SiriusFrame`, `SiriusMessage` 등 프레이밍/메시지 베이스
    - `channel/msgdef/`: protoc-gen-sirius가 생성한 Swift 래퍼 + opcode 매핑
  - `autogen/msgdef/`:
    - SwiftProtobuf로 생성된 원본 protobuf 타입들
  - `transport/`:
    - `TransportLayer`, `Stream`, `TransportLayerImplementation`
    - `client/` + `server/`: 역할별 추상/구현
    - `client/quic/`, `server/quic/`: QUIC 구현체
    - `server/quic/identity/`: QUIC 서버 인증서/신원(Identity) 구현
    - `quic/`: 공통 QUIC 유틸/상수
  - `feature/`:
    - `FeatureProvider` (기능 지원 여부/채널 생성 위임)
  - `logging/`:
    - `SiriusLogger` (OSLog/콘솔 대상)
  - `osapi/security/`:
    - Keychain/인증서/신원 관련 헬퍼 래퍼 (`SRKeychain`, `SRSecurity` 등)
  - `SiriusKit.docc/`: DocC 문서 리소스
  - `SiriusProtocol.swift`, `SiriusSession.swift`, `SiriusKitMeta.swift` 등 공통 타입

# XCODE TARGETS (SiriusKit.xcodeproj)

- 프레임워크 타겟이 **SiriusKit** / **SiriusKitClient**로 분리되어 있습니다.
- 두 타겟 모두 `SiriusKit/` 루트를 공유하지만, PBXFileSystemSynchronized 예외로 역할별 소스를 제외합니다.
  - **SiriusKit (server 역할 중심)**: 클라이언트 전용 파일 제외
    - 제외: `client/**`, `channel/MainChannel+Client.swift`, `transport/client/**`
  - **SiriusKitClient (client 역할 중심)**: 서버 전용 파일 제외
    - 제외: `server/**`, `channel/MainChannel+Server.swift`, `transport/server/**`
    - 추가 제외: `transport/server/quic/identity/**`, `SiriusKit.docc`
- 테스트/헬퍼 타겟: `SiriusKitTests`, `SiriusKitTestsHelper`

# CORE TYPES & ROLES

## 1) 세션/빌더
- `SiriusServerBuilder` / `SiriusClientBuilder`:
  - 필수: `FeatureProvider`, `TransportProtocol` 설정
  - `build()`는 `Result` 반환 (필수 구성 누락 시 에러)
- `SiriusServer`:
  - `ServerRoleRootTransport`를 통해 리스닝
  - 연결 수락 시 `ClientSession` 생성
- `ClientSession` (서버 역할):
  - `ServerRoleClientTransport` 기반
  - `ChannelManager`를 통해 스트림/채널 관리
- `SiriusClient` (클라이언트 역할):
  - `ClientRoleTransport` 기반
  - `ChannelManager`를 통해 메인 채널 오픈 및 채널 생성

## 2) 프로토콜/피처 정의
- `SiriusProtocolVersion`: 32-bit (major/minor/revision) 구조
  - `.v1_0` = `0x0001_0000`
- `SiriusFeature`: UUID 기반 기능 식별자
  - `.hidio`, `.projection`, `.projectionData` 등
- `SiriusKitMeta`: 프레임워크 버전 및 `currentProtocolVersion`

## 3) Channel 레이어
- `Stream` → `Channel` → `MainChannel` 계층
- `ChannelManager`:
  - 클라이언트: `clientOpenMainChannel()`로 첫 스트림을 메인 채널로 생성
  - 서버: 첫 스트림을 메인 채널로 간주
  - `openChannel(...)`은 `ChannelStartRequest/Response` 핸드셰이크 수행
- `shouldAcceptChannelCreation`:
  - 인증 전/후 등 시점에 따라 원격 채널 생성 수락을 제어
- `ChannelDirection`: `.local` / `.remote`
- `Channel.HasFeature` 프로토콜로 채널의 feature 식별 가능

## 4) 메시지 & 프레이밍
- `SiriusFrame` = `Opcode(2 bytes) + Length(4 bytes) + Payload`
- `Stream.write`가 프레임 헤더를 구성 (Big-Endian)
- `SiriusMessage`/`SiriusEnum`:
  - SwiftProtobuf 메시지 ↔ Swift 래퍼 변환
- `MessageOpcode` 확장:
  - `general+Sirius.swift`, `session+Sirius.swift`, `channels+Sirius.swift` 등에서 자동 매핑
  - 추가 상수: `.ping`, `.pong`, `.encapsulatedProtocolMessage`

## 5) 트랜스포트/QUIC
- 추상 계층: `TransportLayer`, `ClientRoleTransport`, `ServerRoleClientTransport`, `ServerRoleRootTransport`
- QUIC 구현:
  - 클라이언트: `ClientRoleQUICTransport` + `ClientRoleQUICStream`
  - 서버: `ServerRoleQUICRootTransport` + `ServerRoleQUICClientTransport` + `ServerRoleQUICStream`
  - ALPN: `pl.unstabler.sirius` (`SiriusQUICAlpn.siriusV1`)
  - 기본 포트: `SiriusQUICDefaultPort = 8282`
  - TLS 1.3 설정 및 서버 인증서 검증 콜백 제공

## 6) 보안/인증서
- `QUICServerIdentity`:
  - `getServerIdentity()`로 `SecIdentity` 제공
  - `sanityCheck()`에서 self-signed 허용 검증 수행 가능
- 구현체:
  - `KeychainQUICServerIdentity` (Keychain 기반)
  - `PEMFileQUICServerIdentity` (PEM 파일 기반)
  - `InMemoryQUICServerIdentity` (테스트용)
- `QUICServerIdentityCreationArgs`:
  - self-signed 인증서 생성 파라미터 정의
- `osapi/security`:
  - `SRKeychain`, `SRSecurity`가 Keychain/Trust/Cert 생성/조회 래핑

## 7) 로깅
- `SiriusLogger`:
  - `SiriusLogLevel`, `SiriusLogVerbosity`
  - 대상: `SiriusConsoleLogDestination`, `SiriusOSLogDestination`
  - 전역 설정: `SiriusLogger.configure(...)`, `SiriusLogger.setVerbosity(...)`

## 8) 프로젝션/코덱 옵션 유틸
- `CodecOptionKey` / `CodecOptionValue` / `CodecOptions`
- `CodecOptionsParser.parse(...)`:
  - `!required` 표기로 mandatory/optional 분리
  - 반환 타입: `CodecOptions`
- `CodecOptionsParser.supportedKeys`:
  - `color-format`, `hardware-acceleration`, `level`, `profile`
- `CodecFourCC`, `CodecParameterSetType`, `ProjectionDataFlags` 등

## 9) HIDIO 키코드 유틸
- `LinuxKeycode`:
  - 리눅스 키코드 집합 제공
- `LinuxKeycode+Carbon`:
  - macOS Carbon keycode ↔ Linux keycode 매핑

# SYNOPSIS (UPDATED)

```swift
// 서버 구성
let server = try SiriusServerBuilder()
    .useFeatureProvider(MyFeatureProvider())
    .useTransportProtocol(.quic(
        port: SiriusQUICDefaultPort,
        identitySource: .keychain(label: "com.example.sirius.identity")
    ))
    .build()
    .get()

// 클라이언트 구성
let client = try SiriusClientBuilder()
    .useFeatureProvider(MyFeatureProvider())
    .useTransportProtocol(.quic(host: "127.0.0.1", port: SiriusQUICDefaultPort))
    .build()
    .get()

client.delegate = self
try await server.startup()
try await client.startup()

// 메인 채널 생성 후 이벤트 처리
func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel) {
    Task {
        for await event in mainChannel.events {
            switch event {
            case .receivedServerHello(let hello):
                print("server features: \(hello.supportedFeatures)")
            case .receivedAuthChallenge(let challenge):
                // 인증 로직
                break
            default:
                break
            }
        }
    }

    // 인증 완료 이후에만 원격 채널 생성 허용
    client.shouldAcceptChannelCreation = true
}

// 원하는 시점에 기능 채널 열기
let hidioChannel = try await client.channelManager.openChannel(
    for: .hidio,
    identifier: UUID()
)
```

# RECENT NOTES / CAUTIONS

- `CodecOptionsParser.parse(...)`는 이제 `CodecOptions`를 반환합니다. (`!required` 지원)
- `QUICServerIdentity`는 `getCertificateChain()`를 지원하며, MsQuic 서버 경로에서는 leaf + intermediate 체인을 함께 전송합니다. (self-signed root 제외)
- `PEMFileQUICServerIdentity`는 `.pem` 내 다중 `CERTIFICATE` 블록을 지원합니다. (첫 블록 leaf, 이후 블록 chain)
- `ChannelOpenTask.blockUntilReceiveData()`는 기본 5초 타임아웃이며, 0 이하면 무제한 대기합니다.
- QUIC 스트림 수신 로직은 현재 프레임 단위 고정 길이 수신을 가정합니다. (fragmented read TODO)
- `TransportLayer`의 기본 구현은 비어있으며, QUIC 또는 커스텀 구현이 필요합니다.

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

### Channel Lifecycle 개요

- 서버와 클라이언트는 **필요할 때마다 채널을 생성(open)하고 종료(close)할 수 있습니다.**
- 채널은 서버·클라이언트 어느 쪽에서든 시작할 수 있으며,
  채널 시작 시에는 반드시 **해당 채널이 어떤 기능(feature)을 위한 것인지**를 상대에게 알려야 합니다.
- 채널이 닫히면 해당 채널과 연결된 스트림도 함께 종료됩니다.

## MAIN CHANNEL

모든 Sirius 커넥션에는 반드시 하나의 **메인 채널(main channel)**이 존재해야 합니다.

- 트랜스포트 커넥션이 수립된 직후, 가장 먼저 생성된 스트림/채널을 메인 채널로 간주합니다.
- 메인 채널은 세션 전반에 걸친 공통 제어 흐름을 담당합니다.

메인 채널은 주로 다음과 같은 역할을 수행합니다.

- 프로토콜 핸드셰이크 수행
  - `ClientHello`, `ServerHello` 메시지 교환
- 사용자 인증(Authentication) 처리
  - `AuthChallenge`, `AuthRequest`, `AuthResponse`
- `ServerNotice`와 같이 세션 전체에 영향을 주는 전역 알림 전송
- Keepalive
  - `ping`, `pong`

> 실제 핸드셰이크/인증 로직은 애플리케이션 레벨에서 구현해야 하며,
> SiriusKit은 메시지 타입 및 `MainChannel.events` 스트림만 제공합니다.

# CHANNEL MESSAGES

Sirius 프로토콜에서 사용되는 모든 메시지는 **Protocol Buffers v3**로 정의합니다.

- 공통 메시지 및 메인 채널용 메시지: `msgdef/general.proto`
- 세션 관리 및 인증 관련 메시지: `msgdef/v1/session.proto`
- 채널 시작/종료 관련 메시지: `msgdef/v1/channels.proto`
- 기능별 채널 메시지: `msgdef/v1/channels/**.proto`

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

# PROTOCOL FLOW (REFERENCE)

Sirius 프로토콜의 기본적인 세션 수립 흐름은 다음과 같습니다.

1. 트랜스포트 커넥션 수립
2. 메인 채널 생성
3. 프로토콜 핸드셰이크
4. 사용자 인증
5. 기능별 채널 생성 및 사용

## 1. 커넥션 수립

- 서버와 클라이언트는 QUIC 등 멀티플렉싱을 지원하는 트랜스포트 프로토콜을 사용해
  커넥션을 수립합니다.
- TLS 위에서 동작하는 프로토콜인 경우, 서버 인증서를 검증하여 MITM 공격 등을 방지해야 합니다.

## 2. 메인 채널 생성

- 커넥션이 수립된 직후, **클라이언트는 메인 채널을 생성**해야 합니다.
- 메인 채널 생성은 트랜스포트 레이어에서 첫 번째 스트림을 여는 방식으로 이루어집니다.
- 사전에 정의된 제한 시간 내에 메인 채널이 생성되지 않으면,
  서버는 커넥션을 타임아웃으로 간주하고 종료할 수 있습니다.

## 3. 핸드셰이크

### 3-1. 클라이언트 핸드셰이크 요청

메인 채널이 준비되면, 클라이언트는 서버에게 `ClientHello` 메시지를 전송합니다.

```swift
try await mainChannel.sendClientHello(.init(
    protocolVersion: .v1_0,
    agentName: "NoctilucaClient/1.0"
))
```

### 3-2. 서버 핸드셰이크 응답

서버는 `ClientHello`를 수신한 뒤 검증을 수행하고, `ServerHello` 또는 `ServerNotice`를 전송합니다.

```swift
// 허용 가능한 요청인 경우
try await mainChannel.sendServerHello(.init(
    protocolVersion: .v1_0,
    supportedFeatures: [SiriusFeature.hidio.rawValue, SiriusFeature.projection.rawValue],
    serverName: "Noctiluca Server/1.0",
    motd: nil
))

// 허용 불가능한 요청인 경우
try await mainChannel.sendServerNotice(.init(
    severity: .fatal,
    code: ServerNoticeCode.unsupportedOpcode.rawValue,
    message: "Unsupported protocol version",
    timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
))
```

`supportedFeatures`는 UUID 배열이며, 애플리케이션 레벨에서는 `SiriusFeature` 상수를 사용합니다.

## 4. 사용자 인증 (Authentication)

### 4-1. 인증 방식 제시 (`AuthChallenge`)

```swift
try await mainChannel.sendAuthChallenge(.init(
    acceptedMethods: ["password", "ssh-key"],
    nonce: randomNonce,
    message: "이 컴퓨터는 Acme Corp. 소유입니다. 허가 받지 않은 접근을 금지합니다."
))
```

- `acceptedMethods`는 문자열 배열이며, 실제 의미/포맷은 앱에서 정의합니다.
- `nonce`는 인증 요청/응답에 사용될 임의 바이트 값입니다.

### 4-2. 클라이언트 인증 요청 (`AuthRequest`)

```swift
try await mainChannel.sendAuthRequest(.init(
    method: "password",
    nonce: challenge.nonce,
    payload: encryptedPayload
))
```

### 4-3. 서버 인증 완료 (`AuthResponse`)

```swift
try await mainChannel.sendAuthResponse(.init(sessionID: UUID()))
```

## 5. 채널 생성

채널 생성은 `ChannelStartRequest` / `ChannelStartResponse`로 이루어집니다.
현재 `ChannelStartResponse`는 성공 여부(`success`)만 포함합니다.

```swift
let channel = try await client.channelManager.openChannel(
    for: .projection,
    identifier: UUID(),
    args: []
)
```

</section>
