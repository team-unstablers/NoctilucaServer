<section id="project-info">

# NoctilucaClient

NoctilucaClient는 Noctiluca 원격 제어 솔루션의 **클라이언트 애플리케이션**입니다.  
macOS/iOS에서 실행되며, Sirius 프로토콜(SiriusKitClient)을 통해 원격 호스트와 연결하고
입력(HIDIO) 전송 및 화면 프로젝션 스트림 수신/디코딩을 담당합니다.

# TECHNOLOGIES USED

- Swift / SwiftUI
- Combine
- AVFoundation / VideoToolbox (VTDecompressionSession, AVSampleBufferDisplayLayer)
- GameController (GCKeyboard 등 입력 디바이스 연동)
- SiriusKitClient (Sirius 프로토콜/채널, QUIC via Network.framework)
- Google Protobuf 3 (Sirius msgdef 기반)
- AppKit / UIKit 브리지(NSViewRepresentable, UIViewRepresentable)

# DIRECTORY STRUCTURE

- `NoctilucaClient/`
  - `logic/`: `NoctilucaClient` 세션/페이즈 관리, 핸드셰이크 및 인증 처리
  - `feature/hidio/`: 키보드/마우스 입력 전송 채널 및 가상 디바이스 구현
  - `feature/projection/`: 프로젝션 제어/데이터 채널, 세션 관리, 디코더(VTVideoDecoder)
  - `feature/projection/decoder/specification/`: 코덱 옵션/스펙 보조 타입
  - `models/settings/`: 앱 설정(JSON) + 보안 설정(Keychain)
  - `ui/`: AppKit/SwiftUI/UIView 기반 UI, 설정 창/세션 화면/모바일 UI
  - `utils/`: 로깅/JSON 유틸
  - `auth/`: PAM 인증 페이로드 인코딩/검증

# RUNTIME FLOW (HIGH-LEVEL)

1. UI(`MainWindowViewModel`)에서 `SiriusClientBuilder`로 세션 생성
2. `NoctilucaClient`가 MainChannel 이벤트 루프를 돌며 `ServerHello`/`AuthChallenge`/`AuthResponse` 처리
3. 인증 완료 시 HIDIO/Projection 채널을 열고 프로젝션 세션 생성
4. `ProjectionDataChannel`에서 코덱 파라미터 세트/프레임 수신
5. `VTVideoDecoder`가 VideoToolbox로 디코드 → `AVSampleBufferDisplayLayer`로 렌더링

# ENTRY POINTS & APP LIFECYCLE

- macOS
  - `NoctilucaClient/NoctilucaClientApp+macOS.swift`: `@main` App, 메인 창 및 설정 창 생성
  - `NoctilucaClient/AppDelegate+macOS.swift`: 앱 시작 시 GCKeyboard lifecycle 리스너 등록
  - 메인 창: `AppKitMainWindow` → `MainWindowContentView`
  - 설정 창: `AppKitSettingsWindow`
- iOS
  - `NoctilucaClient/NoctilucaClientApp+iOS.swift`: `@main` App, EmptyView + Scene 활성화
  - `NoctilucaClient/AppDelegate+iOS.swift`: `MobileUIMainSceneDelegate` 지정
  - Scene: `MobileUIMainSceneDelegate` → `MobileUIMainView` (NavigationStack 기반)
  - 설정 창: `UIKitSettingsWindow`

# CORE MODULES (CODE MAP)

- Session / Protocol
  - `logic/NoctilucaClient.swift`: 페이즈 관리, MainChannel 이벤트 루프, ping/pong RTT 측정
  - `logic/NoctilucaClient+Auth.swift`: ClientHello/AuthChallenge/AuthResponse 처리
  - `logic/NoctilucaClient+Main.swift`: HIDIO/Projection 채널 초기화 및 세션 시작
- Feature Provider
  - `feature/NoctilucaFeatureProvider.swift`: Sirius feature → 채널 타입 매핑
- Projection
  - `feature/projection/ProjectionChannel.swift`: Projection 요청/세션 생성 및 관리
  - `feature/projection/ProjectionDataChannel.swift`: 프레임/파라미터 세트 수신
  - `feature/projection/ProjectionSession.swift`: 디코더 + 렌더링 + 성능 리포팅
  - `feature/projection/decoder/VideoDecoder.swift`: 디코더 인터페이스 및 데이터 모델
  - `feature/projection/decoder/VTVideoDecoder.swift`: VideoToolbox 기반 디코더 구현
  - `feature/projection/decoder/specification/*`: 코덱 스펙, HDR/10-bit 지원 판정, 해상도 레벨
- HIDIO (Input)
  - `feature/hidio/HIDIOChannel.swift`: HIDIO 채널
  - `feature/hidio/HIDIOController.swift`: 키보드/마우스 이벤트 패킷 전송
  - `feature/hidio/devices/*`: GCKeyboard 기반 가상 디바이스 및 키코드 매핑
- UI
  - `ui/views/main/*`: 주소창/연결 상태/스트리밍 화면
  - `ui/views/session*`: 세션 설정 UI
  - `ui/views/settings/*`: 앱 설정 UI
  - `ui/windows/*`: 플랫폼별 창/툴바 구성

# PROTOCOL / CHANNEL FLOW (DETAIL)

- 세션 생성
  - `MainWindowViewModel.startSession(...)` → `SiriusClientBuilder`
  - `.useTransportProtocol(.quic(host:port))` + `.useFeatureProvider(NoctilucaFeatureProvider())`
- 메인 채널
  - `NoctilucaClient`가 `MainChannel` 이벤트 수신
  - `ServerHello` 수신 → `awaitingAuthentication`
  - `AuthChallenge` 수신 → UI로 전달 → `AuthRequest` 전송
  - `AuthResponse` 수신 → `.ready` 전환, 추가 채널 생성 허용
- HIDIO 채널
  - `HIDIOChannel`은 클라이언트에서만 open
  - `HIDIOController`가 `HIDIOPacket`으로 키 이벤트 전송
  - `GCKeyboard` 입력을 `LinuxKeycode`로 변환 (`LinuxKeycode+GameController`)
- Projection 채널
  - `ProjectionChannel.createSession()`에서 `ProjectionRequest` 송신
  - 서버가 `ProjectionSessionCreatedEvent`를 반환하면 `ProjectionDataChannel` 생성됨
  - `ProjectionSession`이 디코더 준비/시작 + 성능 리포트 주기 전송

# PROJECTION DATA FORMAT / DECODER DETAILS

- ProjectionDataChannel 프레임 포맷 (big-endian)
  - `<headerLength: uint32> <frameLength: uint32> <headerBytes> <frameBytes>`
  - `FrameDataHeader`는 Protobuf (Sirius msgdef)
- 코덱 파라미터 세트
  - `CodecParameterSetMessage` 수신 시 `CMFormatDescription` 생성
- VTVideoDecoder
  - `VTDecompressionSession` 생성 (하드웨어 가속 요구 설정 포함)
  - `Codec` 옵션을 기반으로 `CVPixelBuffer` 포맷 결정 (YUV420/444, 8/10-bit, full/limited range)
  - `CMSampleBufferCreateReady`로 샘플버퍼 생성 후 디코딩
  - 출력 콜백에서 `DecodedFrame` 생성 및 delegate 전달
  - `VTSessionSetProperty(...GeneratePerFrameHDRDisplayMetadata)` 활성화

# UI OVERVIEW

- 메인 페이즈
  - `MainWindowContentView`가 `newConnection`/`connecting`/`connected` 상태에 따라 화면 분기
  - `MainWindowMainPhaseContentView`에서 `AVSampleBufferDisplayLayer`를 표시하고 확대/이동 제스처 지원
- 주소창/툴바
  - `AddressBar` + `AddressBarCandidateBox` + `AddressBarIndicatorView`
  - RTT 기반 품질 표시, 보안 상태 아이콘, 후보 목록 (quick connect / contact)
  - macOS: 커스텀 NSToolbar (`MainToolbar`)
  - iOS: `View+iOSToolbar.swift`로 디바이스별 툴바 오버레이
- 인증 UI
  - `AuthChallengeSheetView`에서 PAM 기반 username/password 입력
  - macOS: sheet, iOS: fullScreenCover
- 디버그
  - `PerformanceOverlay`에서 협상된 코덱/RTT 표시

# SETTINGS & STORAGE

- 설정 모델: `models/settings/AppSettings.swift`
  - 일반/알림/프로젝션/보안/트랜스포트/QUIC/텔레메트리 섹션
  - JSON 저장 위치: `Application Support/<bundle id>/settings.json`
  - 보안 항목은 `SRKeychain`을 통해 Keychain 저장
- 프로젝션 설정
  - `ProjectionSettings`에서 기본 코덱 스펙 리스트(`CodecSpecification`) 관리
  - 세션 설정 UI에서 코덱 우선순위/협상 정책 편집 가능

# DATA MODEL / HELPERS

- `NoctilucaMeta`: 앱 이름/버전/빌드/라이선스 및 identifier 헬퍼
- `DeviceKind`: iPhone/iPad/mac 구분
- `JSON` 유틸: snake_case 변환 포함 인코딩/디코딩 헬퍼
- `Binding+Convert`: 숫자 타입 바인딩 변환
- `SoftwareLicense`: 라이선스 enum 정의

# AUTH / PAYLOAD

- `auth/pam/PAMAuthPayload.swift`
  - payload 포맷: `[u32 usernameLen][u32 passwordLen][username][password]`
  - 유효성 검증/추출 helper 제공

# KNOWN TODO / FIXME (요약)

- `ContentView.swift`: `FIXME__ContentViewModel`는 임시 연결 UI
- `NoctilucaClient.swift`: `FIXME_projectionStarted` 이벤트로 디코더 시작 알림 임시 전달
- `VTVideoDecoder.swift`: 하드웨어 디코딩 실패 시 소프트웨어 폴백 미구현
- `ProjectionSession.swift`: 샘플 타이밍/PTS 정규화 로직 일부 주석 처리
- `AuthChallengeSheetView.swift`: PAM 외 인증 플러그인 인터페이스 분리 필요, 비밀번호 메모리 정리 필요
- `SecuritySessionSettingsTab.swift`: 인증서 고정 UI/정보 표시 미구현
- UI 전반: AddressBar 후보/키 입력 처리 등 TODO/FIXME 다수

# XCODE / BUILD NOTES

- `NoctilucaClient.xcodeproj`가 기본 프로젝트 (scheme: `NoctilucaClient`, product: `Noctiluca Navigator.app`)
- `NoctilucaClient 2.xcodeproj`는 사용자 데이터만 포함 (실사용 전 확인 필요)

# CONFIG / STATE

- 설정 파일: `Application Support/<bundle id>/settings.json`
- 보안 항목: `SRKeychain`을 사용해 Keychain 저장

# RELATED PROJECTS

- `../SiriusKit`: Sirius 프로토콜 정의 및 전송 계층 구현
  - `CodecOption`/`CodecOptionsParser` 등 공용 타입은 SiriusKit 쪽을 기준으로 사용
- `../NoctilucaServer`: 서버 애플리케이션(호스트) 구현
  - 프로젝션/입력/인증 흐름의 실제 서버 동작은 이쪽을 기준으로 확인

## Recommended Core Paths

SiriusKit (프로토콜/채널/전송 기준):
- `../SiriusKit/SiriusKit/client/SiriusClient.swift`
- `../SiriusKit/SiriusKit/client/SiriusClientBuilder.swift`
- `../SiriusKit/SiriusKit/channel/MainChannel.swift`
- `../SiriusKit/SiriusKit/channel/Channel.swift`
- `../SiriusKit/SiriusKit/channel/ChannelManager.swift`
- `../SiriusKit/SiriusKit/channel/messages/SiriusFrame.swift`
- `../SiriusKit/SiriusKit/channel/msgdef/v1/channels/projection/CodecOption.swift`
- `../SiriusKit/SiriusKit/channel/msgdef/v1/channels/projection/CodecOptionsParser.swift`
- `../SiriusKit/SiriusKit/transport/client/quic/ClientRoleQUICTransport.swift`
- `../SiriusKit/SiriusKit/transport/quic/QUICConstants.swift`

NoctilucaServer (서버 동작/핸들러 기준):
- `../NoctilucaServer/NoctilucaServer.swift`
- `../NoctilucaServer/NoctilucaServerApp.swift`
- `../NoctilucaServer/client-session/NoctilucaClientSession.swift`
- `../NoctilucaServer/client-session/NoctilucaClientSession+Auth.swift`
- `../NoctilucaServer/feature/projection/ProjectionChannel.swift`
- `../NoctilucaServer/feature/projection/ProjectionDataChannel.swift`
- `../NoctilucaServer/feature/projection/encoder/VTVideoEncoder.swift`
- `../NoctilucaServer/feature/projection/recorder/ScreenCaptureKitScreenRecorder.swift`
- `../NoctilucaServer/feature/hidio/HIDIOChannel.swift`
- `../NoctilucaServer/auth/Authenticator.swift`
- `../NoctilucaServer/auth/AuthPluginRegistry.swift`

## Context Resolve Rule

컨텍스트 해석(Context Resolve)이 필요한 경우에는 **반드시**  
`../SiriusKit`와 `../NoctilucaServer`를 함께 확인한 뒤 진행하세요.  
아래 체크리스트를 충족하지 못하면 **코드 변경을 진행하지 않습니다.**

Context Resolve Checklist:
1. 관련 메시지/옵션 정의는 `../SiriusKit`의 msgdef/채널 래퍼에서 확인했다.
2. 클라이언트 측 호출 흐름은 `../SiriusKit`의 client/channel 구현과 대조했다.
3. 서버 측 처리 로직은 `../NoctilucaServer`의 client-session/feature 구현과 대조했다.
4. 위 1~3의 결과가 클라이언트 변경과 충돌하지 않는지 점검했다.

## Recent Notes

- `CodecOptionsParser.parse(optionsString:)`는 이제 `[CodecOptionKey: CodecOptionValue]` 대신
  `CodecOptions`(mandatory/optional, `!required` 지원)을 반환합니다.
- `CodecOption`/`CodecOptionsParser` 정의가 `SiriusKit/channel/msgdef/v1/channels/projection`로 이동했고,
  클라이언트에서도 사용할 수 있도록 `public`으로 노출되었습니다.
- 디코더 설계 문서: `DECODER_PLAN.md` (VideoToolbox 기반 디코딩 계층 설계 초안)
- `ProjectionSession`은 매 1초마다 `ProjectionPerformanceReport`를 전송해 디코드 성능을 리포트합니다.
- UI/세션/디코더 주변에 FIXME/TODO가 다수 존재하므로 변경 시 범위 확인 필요

</section>
<section id="agent-rules">

# AGENT RULES

## 1. Interaction & Language
- 작업을 진행할 때 확실하지 않거나 궁금한 점이 있으면, 되도록 **추측하지 말고 사용자에게 질문**해서 명확히 하는 것을 우선해 주세요.
- 사용자가 한국어 화자인 만큼, 모든 대화와 Plan 작성은 **반드시 한국어**로 진행해 주세요.
- 프로젝트에 대한 중요한 정보나 커다란 변경 사항이 있을 때는, `AGENTS.md`를 수정하여 프로젝트에 대한 최신 정보를 반영해 주세요.
- 컨텍스트 해석(Context Resolve)이 필요한 경우에는 **반드시** `../SiriusKit`와 `../NoctilucaServer`를 함께 참조해 주세요.

## 2. Workflow Protocol (중요)
Codex는 기본적으로 자율적(Autonomous)으로 행동하지만, 아래의 **[Explicit Plan Mode]** 조건에 해당할 경우 행동 방식을 변경해야 합니다.

### [Explicit Plan Mode] 트리거 조건
1. 사용자가 명시적으로 **'Plan 모드'**, **'계획 모드'**, 또는 **'설계 먼저'**라고 요청한 경우.
2. 작업이 **3개 이상의 파일**에 구조적 변경을 일으키거나, **Core Logic(Protobuf, Network, AVFoundation)**을 건드리는 위험한 변경일 경우.

### [Explicit Plan Mode] 행동 수칙
위 조건이 발동되면 **즉시 코드 구현을 멈추고** 다음 절차를 따르세요:
1. **Stop:** 코드를 작성하거나 수정하지 마십시오. (파일 읽기는 가능)
2. **Plan:** `update_plan` 도구를 사용하여 **한국어**로 상세 구현 계획, 영향 범위, 예상 리스크를 작성하십시오.
3. **Ask:** 사용자에게 계획을 제시하고 **"이대로 진행할까요?"**라고 승인을 요청하십시오.
4. **Action:** 사용자의 명시적 승인(예: "ㅇㅇ", "진행해")이 떨어진 후에만 코드를 수정하십시오.

*(위 조건에 해당하지 않는 단순 수정이나 버그 픽스는 기존대로 승인 없이 즉시 처리하고 결과를 보고하십시오.)*

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
