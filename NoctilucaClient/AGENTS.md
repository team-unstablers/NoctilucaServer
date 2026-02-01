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

# MULTI-PLATFORM SUPPORT

- 이 앱은 macOS / iOS 멀티 플랫폼을 지원합니다.
- platform-specific 코드(AppKit / UIKit 등)는 `app/macos` 및 `app/ios` 디렉토리로 분리되어 있습니다.

# DIRECTORY STRUCTURE

- `NoctilucaClient/`
  - `core/`: 모든 플랫폼에서 공유하는 핵심 로직 및 UI
    - `logic/`: `NoctilucaClient` 세션/페이즈 관리, 핸드셰이크 및 인증 처리
    - `feature/`: 기능별 구현 (HIDIO, Projection 등)
    - `models/`: 데이터 모델 (설정, 연락처 등)
    - `state/`: 전역 상태 관리 (`RemoteSession` 등)
    - `auth/`: 인증 플러그인 및 구현체
    - `ui/`: 플랫폼 공용 SwiftUI 뷰 및 컴포넌트
    - `utils/`, `compat/`, `extensions/`: 유틸리티 및 호환성 코드
  - `app/`: 플랫폼별 애플리케이션 코드
    - `ios/`: iOS 전용 (AppDelegate, Mobile UI, Input View 등)
    - `macos/`: macOS 전용 (AppDelegate, AppKit Window/View, TCC 등)
  - `resources/`: 공용 리소스 (Assets, Icons, Info.plist, Bridging Header)

# RUNTIME FLOW (HIGH-LEVEL)

1. UI(`SessionWindowViewModel`)에서 `RemoteSession` 생성/연결 트리거 → `NoctilucaClientManager`로 세션 생성
2. `NoctilucaClient`가 MainChannel 이벤트 루프를 돌며 `ServerHello`/`AuthChallenge`/`AuthResponse` 처리
3. 인증 완료 시 HIDIO/Projection 채널을 열고 프로젝션 세션 생성
4. `ProjectionDataChannel`에서 코덱 파라미터 세트/프레임 수신
5. `VTVideoDecoder`가 VideoToolbox로 디코드 → `AVSampleBufferDisplayLayer`로 렌더링

# ENTRY POINTS & APP LIFECYCLE

- macOS (`app/macos`)
  - `AppDelegate+macOS.swift`: `@main` AppKit(NSApplicationDelegate)
  - `ui/main/AppKitMainWindowController.swift`: 메인 윈도우 컨트롤러
- iOS (`app/ios`)
  - `NoctilucaClientApp+iOS.swift`: `@main` SwiftUI App
  - `ui/main/mobile/MobileUIMainSceneDelegate.swift`: Scene Delegate

# CORE MODULES (CODE MAP)

- Session / Protocol (`core/logic`)
  - `NoctilucaClient.swift`: 페이즈 관리, MainChannel 이벤트 루프, ping/pong RTT 측정
  - `NoctilucaClient+Auth.swift`: ClientHello/AuthChallenge/AuthResponse 처리
  - `NoctilucaClient+Main.swift`: HIDIO/Projection 채널 초기화 및 세션 시작
- Feature Provider (`core/feature`)
  - `NoctilucaFeatureProvider.swift`: Sirius feature → 채널 타입 매핑
- Projection (Video) (`core/feature/projection`)
  - `ProjectionChannel.swift`: Projection 요청/세션 생성 및 관리
  - `ProjectionDataChannel.swift`: 프레임/파라미터 세트 수신
  - `ProjectionSession.swift`: 디코더 + 렌더링 + 성능 리포팅
  - `decoder/VideoDecoder.swift`: 디코더 인터페이스 및 데이터 모델
  - `decoder/VTVideoDecoder.swift`: VideoToolbox 기반 디코더 구현
- Audio Projection (`core/feature/projection`)
  - `AudioProjectionSession.swift`: 오디오 디코딩 + AVAudioEngine 재생
  - `decoder/AudioDecoder.swift`: 오디오 디코더 인터페이스
- HIDIO (Input) (`core/feature/hidio`)
  - `HIDIOChannel.swift`: HIDIO 채널
  - `HIDIOController.swift`: 키보드/마우스 이벤트 패킷 전송
  - `devices/*`: 가상 입력 디바이스 구현체

# UI OVERVIEW

- 메인 페이즈 (`core/ui/main`)
  - `MainWindowContentView`: 연결 상태에 따른 화면 분기
  - `phases/*`: 각 연결 단계별 UI
- 주소창/툴바 (`core/ui/main/address-bar`)
  - `AddressBar`: 연결 주소 입력 및 상태 표시
- 설정 (`core/ui/settings`, `core/ui/session-settings`)
  - 앱 설정 및 세션별 설정 UI

# XCODE / BUILD NOTES

- **클라이언트 빌드 시 반드시 xcworkspace를 사용하여 빌드하십시오.**
- 디렉토리 구조 변경으로 인해 Xcode 프로젝트 그룹이 실제 폴더 구조(`core`, `app`, `resources`)와 일치해야 합니다.

# RELATED PROJECTS

- `../SiriusKit`: Sirius 프로토콜 정의 및 전송 계층 구현
- `../NoctilucaServer`: 서버 애플리케이션(호스트) 구현

## Context Resolve Rule

컨텍스트 해석(Context Resolve)이 필요한 경우에는 **반드시**  
`../SiriusKit`와 `../NoctilucaServer`를 함께 확인한 뒤 진행하세요.

## Recent Notes

- **2026-02-01**: RemoteApp 지원 준비를 위해 **디렉토리 구조 리팩토링**을 수행했습니다. (`core`, `app`, `resources` 분리)
- **오디오 프로젝션 기능 구현 완료**: `AudioProjectionSession`, `AudioDecoder` 등
- **ZRLE 디코더 추가**: `ZRLEVideoDecoder` (RLE + Zstd)

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
