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
- **종료 시퀀스 정리**: `NoctilucaClient.close()`는 task 취소 후 `mainChannel` 참조를 명시적으로 해제하고, `SiriusClient.shutdown()`은 transport disconnect 전에 채널 teardown을 수행합니다. 접속 중 종료 시 MsQuic retain chain을 끊기 위한 변경입니다.

</section>
