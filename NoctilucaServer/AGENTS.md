<section id="project-info">

# NoctilucaServer

NoctilucaServer는 Noctiluca 원격 제어 시스템의 **macOS 호스트(서버) 애플리케이션**입니다.
SiriusKit을 사용해 클라이언트 세션을 수락하고, 인증·입력 이벤트(HIDIO)·화면 전송(Projection)을 처리합니다.
메뉴바 기반 UI와 설정 창을 제공하며, 플러그인 번들로 인증 모듈을 확장할 수 있습니다.

# TECHNOLOGIES USED

- Swift / SwiftUI
- SiriusKit (Sirius 프로토콜, QUIC/Network.framework, Protobuf)
- ScreenCaptureKit + AVFoundation(AVCaptureSession)
- VideoToolbox (H.264/H.265 인코딩)
- CoreGraphics / CoreMedia
- Keychain (보안 설정 저장)

# DIRECTORY STRUCTURE

- `NoctilucaServerApp.swift` - `@main` App, Settings Window + MenuBarExtra 구성
- `AppDelegate.swift` - 앱 런치 훅 (`applicationDidFinishLaunching`), 창 닫힘 정책
- `NoctilucaServer.swift` / `ServerContext.swift` - 서버 싱글턴, SiriusServer 구성/시동, 상태 관리, 세션 수락
- `NoctilucaMeta.swift` - 앱 메타(이름/버전/라이선스/번들 ID)
- `client-session/` - 메인 채널 이벤트 루프, 핸드셰이크/인증, 세션 상태 머신
  - `NoctilucaClientSession.swift`
  - `NoctilucaClientSession+Auth.swift` / `NoctilucaClientSession+Notice.swift`
- `feature/` - Sirius FeatureProvider 및 채널 구현
  - `NoctilucaFeatureProvider.swift`
  - `feature/hidio/` - 키보드/마우스 이벤트 인젝션 채널
  - `feature/projection/` - 프로젝션 채널/세션, ScreenRecorder(SCK/AVF), VideoEncoder(VT), 코덱 협상/품질 플래너
- `projection/` - 디스플레이 레이아웃/윈도우/데스크톱 컨텍스트 관리
  - `DisplayLayoutManager.swift` (디스플레이 변화 모니터)
  - `DesktopContextManager.swift` (앱/윈도우 관찰, AX 이벤트)
- `auth/` - 인증기/레지스트리, AuthMethod 정의, bcrypt/passwd 유틸
- `plugins/` - 플러그인 번들 시스템(외부/내장), 기본 인증 플러그인
  - `plugins/bundle-system/` - 번들 메타데이터 파싱/검증, 레지스트리, 보안 정책
  - `plugins/builtins/` - 내장 플러그인 번들 등록 및 메타데이터
  - `plugins/builtins/auth/` - 기본 인증 번들(`NoctilucaCoreAuth`) + PAM/SimplePassword/Null
- `models/settings/` - `AppSettings` (JSON + Keychain)
- `ui/`
  - `MainTrayMenuContents.swift` - 메뉴바 트레이 UI (서버 시작/중지)
  - `windows/SettingsWindow.swift` - 설정 창(TabView)
  - `windows/constrainted/` - ScreenCaptureKit workaround 더미 윈도우
  - `views/settings/` - 설정 탭별 UI
- `utils/` - 로깅/JSON/TCC/C 인터롭 유틸
- `NoctilucaServer-Bridging-Header.h` - PAM 플러그인 ObjC 헤더 노출

# ENTRY POINTS & APP LIFECYCLE

- `NoctilucaServerApp`가 `@main`으로 앱 엔트리이며 `@StateObject var server = NoctilucaServer.shared`로 서버 싱글턴을 UI 수명주기와 연결합니다.
- 설정 창(`SettingsWindow`)은 `Window(...).defaultLaunchBehavior(.suppressed)`로 기본 표시를 막고, 메뉴바 트레이에서 열도록 구성합니다.
- 메뉴바 트레이(`MenuBarExtra`)는 `.menu` 스타일이며 `MainTrayMenuContents`에서 서버 시작/중지/설정/종료 액션을 제공합니다.
- `AppDelegate.applicationDidFinishLaunching`에서 현재는 `print("Hello, World!")`만 수행합니다(메뉴바 앱 활성 정책 등은 TODO).
- `applicationShouldTerminateAfterLastWindowClosed`는 `false`를 반환하여 마지막 창이 닫혀도 앱이 종료되지 않습니다.

# INIT / STARTUP FLOW (SERVER)

1. `NoctilucaServer.init()`에서
   - `Authenticator`/`NoctilucaServerContext` 생성
   - `SiriusLogger.configure(minimumLevel: .trace)` 호출(현재는 init에서 수행, TODO: AppDelegate로 이동)
   - 비동기 `initialize()` 호출
2. `initialize()`에서
   - `DisplayLayoutManager.shared.startMonitoring()` + `updateDisplayLayouts()`
   - `AppSettings.load()` (Application Support JSON + Keychain secure entries)
   - `pluginBundleRegistry.registerBuiltinBundles()`로 내장 번들 등록
   - `authenticator.setupAllowedEntires(settings.security.allowedEntries)`
   - `ScreenCaptureKitWorkaroundDummyWindow.windowManager.startup()` (디스플레이별 더미 윈도우 생성)
3. UI에서 서버 시작 시 (`MainTrayMenuContents`):
   - `NoctilucaServer.startup()` 호출 → 상태 `idle → preparing`
   - 기본 Keychain identity 확인/생성 (`defaultKeychainIdentity`)
   - `SiriusServerBuilder`로 QUIC/FeatureProvider 설정 후 `server.setup()` + `server.startup()`

# SERVER STATE / CONTEXT

- `NoctilucaServerState`: `.idle` / `.preparing` / `.running(server: SiriusServer)`
- `NoctilucaServerContext`는 `ServerContext`를 구현하며 FeatureProvider, Authenticator, AppSettings에 대한 read-only 브리지를 제공합니다.
- `serverName(withVersion:)`는 `NoctilucaMeta.productName`과 버전을 조합해 반환합니다.

# CLIENT SESSION FLOW (MAIN CHANNEL)

- `NoctilucaClientSession`은 `ClientSessionDelegate`를 구현하며 메인 채널 이벤트 루프를 운영합니다.
- 세션 페이즈:
  - `.initial` → `.awaitingAuthentication` → `.ready` → `.closed` (`.panic` 포함)
- `initialize()` 시 5초 내 `ClientHello` 수신을 요구하는 `phaseShiftAssertion` 시작.
- `handleClientHello`:
  - 프로토콜 버전 `.v1_0`만 허용
  - `ServerHello` + `AuthChallenge` 발송
  - 60초 내 인증 완료 요구
- `handleAuthRequest`:
  - 메소드/nonce 검증 → `Authenticator.authenticate` 시도
  - 실패 시 지연(3s, 6s, 9s ...; 최소 10s) + 재챌린지
  - 최대 시도(`settings.security.maxLoginAttempts`) 초과 시 세션 종료
  - 성공 시 `.ready`, `AuthResponse(sessionID)` 전송, `session.shouldAcceptChannelCreation = true`
- 세션 종료 시 `ProjectionChannel`이 있으면 `destroy()`로 세션 정리 후 `ClientSession.close()`.

# FEATURE PROVIDER & CHANNEL MAP

- `NoctilucaFeatureProvider`가 지원 기능을 선언:
  - `.hidio`, `.projection`, `.projectionData`
- 기능별 채널 생성:
  - `.hidio` → `HIDIOChannel`
  - `.projection` → `ProjectionChannel`
  - `.projectionData` → `ProjectionDataChannel`

# PROJECTION PIPELINE (SERVER)

- `ProjectionChannel` (remote open)에서 `ProjectionRequest` 수신
  - `CodecNegotiator`(현재 `.balanced`)로 서버 설정 `ProjectionSettings.codecSpecifications`와 클라이언트 요청을 협상
  - 동일 `identifier`로 `ProjectionDataChannel` 생성
  - `ProjectionSession.prepare()` → `start()`
  - `ProjectionSessionCreatedEvent` 전송
- `ProjectionSession`:
  - `ScreenCaptureKitScreenRecorder` + `VTVideoEncoder` 사용
  - `encoder.events`를 통해 파라미터 세트/프레임 전송
  - `ProjectionPerformanceReport`와 `writeBackPressure`를 기반으로 `AutoQualityPlanner`가 bitrate 조정
  - backpressure가 임계치 초과 시 프레임 드롭 + flush 후 keyframe 요청
- `ProjectionDataChannel` 프레임 포맷:
  - `<headerLen: u32><frameLen: u32><headerBytes><frameBytes>` (Big-Endian)
  - `SiriusFrame(opcode: .frameData)`로 감쌈

# SCREEN CAPTURE & DISPLAY LAYOUT

- `DisplayLayoutManager`:
  - `CGDisplayRegisterReconfigurationCallback`로 디스플레이 변경 감시
  - `displayLayouts: [CGDirectDisplayID: CGRect]` 게시
- `ConstraintedNSWindowManager`:
  - 디스플레이 변화에 따라 각 화면에 "제약된 윈도우"를 생성/정리
- `ScreenCaptureKitWorkaroundDummyWindow`:
  - 1x1, 투명, 마우스 이벤트 무시, 모든 Space에 존재
  - ScreenCaptureKit의 "exclude window 없음" 제약 우회용
- `ScreenCaptureKitScreenRecorder`:
  - `.entireDisplay`만 지원
  - `SCContentFilter`에서 더미 윈도우를 제외 목록에 포함
  - `minimumFrameInterval`, HDR preset, cursor 표시 여부 설정
- `AVFoundationScreenRecorder`:
  - `AVCaptureSession` + `AVCaptureScreenInput` 기반, 호환성 폴백용

# HIDIO PIPELINE

- `HIDIOChannel`은 `HIDIOPacket`을 파싱해 키보드 이벤트를 `EventInjector`로 주입합니다.
- `EventInjector`는 `CGEventSource` 기반이며, key down/up 시 modifier 상태를 보정합니다.
- 마우스 이벤트 주입은 코드 구조만 준비되어 있고 일부 TODO 상태입니다.

# AUTHENTICATION FLOW

- `Authenticator`는 `AuthPluginRegistry`의 플러그인을 순차적으로 호출해 인증합니다.
- 성공 시 `uid_t` 반환, 실패 시 `.authenticationFailed`.
- payload는 인증 후 `memset_s`로 zeroize 처리합니다.

# PLUGIN SYSTEM (SERVER SIDE)

## Bundle Loader/Registry
- `PluginBundleRegistry`가 번들 URL에서 `Bundle`을 로드하고 `PluginBundlePlistMetadata`(Info.plist 기반)를 파싱합니다.
- 번들 `principalClass`는 `NoctilucaPluginBundle`을 채택해야 하며, `initialize()` 성공 후에만 등록됩니다.
- 메타데이터 검증: **Info.plist의 export 목록 수/ID/타입**이 실제 `exports`와 1:1 매칭되어야 로딩됩니다.
- 등록 시 현재는 `.auth` 타입만 `AuthPluginRegistry`로 라우팅됩니다 (`NoctilucaPluginExport` 스위치).
- `registerBundle()`는 `initialize()` 실패 시 `deinitialize()`를 시도하고 `.initializationFailed`로 종료합니다.
- registry `deinit`에서 로드된 모든 번들에 대해 `deinitialize()`를 호출합니다.

## Built-in Bundles
- `PluginBundleRegistry.registerBuiltinBundles()`에서 내장 번들을 등록합니다.
- `NoctilucaCoreAuth` 번들은 기본 인증 플러그인을 제공하며,
  - Release: `PAMAuthPlugin`, `SimplePasswordAuthPlugin`
  - Debug: `NullAuthPlugin` 추가
- `NoctilucaServer-Bridging-Header.h`를 통해 `PAMAuthPlugin.h`를 Swift에 노출합니다.
- `SimplePasswordAuthPlugin` 페이로드는 **raw password bytes**이며, 서버 측에서 sha512+bcrypt 검증을 수행합니다.

## Info.plist 기반 메타데이터
- `PluginBundlePlistMetadata`/`PluginBundleExportPlistMetadata`가 `NoctilucaPluginKit`의 plist 키 스펙으로 파싱됩니다.
- 라이선스는 SPDX 식별자 문자열을 `SoftwareLicense.from(spdxIdentifier:url:)`로 매핑합니다.
  - `CUSTOM:`/`PROPRIETARY:` 접두어 지원

## Security Policy
- `PluginBundleSecurityPolicy`:
  - `disallowAll` / `allowTeamUnstablers` / `allowSigned` / `allowAll`
- 현재 레지스트리의 실제 정책 검증은 TODO로 남아있고 기본값은 `allowTeamUnstablers`입니다.

# SETTINGS & STORAGE

- `AppSettings`는 다음 카테고리로 구성됩니다:
  - `General`, `Notifications`, `Projection`, `Security`, `Transport`, `QUICTransport`, `Telemetry`
- `General`: `maxConcurrentSessions` (기본 1)
- `Projection`: `preferredScreenRecorder`(기본 `.screenCaptureKit`), `codecSpecifications` 기본값 `[.hevc, .h264]`
- `Security`: `allowedEntries`(Keychain 저장), `maxLoginAttempts` (기본 3)
- `Transport`: 서버 버전/지원 기능 공개 여부, `motd`, `authChallengeMessage`
- `QUICTransport`: `listenPort`(기본 `SiriusQUICDefaultPort`), TLS 자동 구성/엄격 검증 옵션, `identity`(Keychain/PEM)
- 저장 위치:
  - JSON: `Application Support/<bundle id>/settings.json`
  - Secure entries: Keychain (`SRKeychain`)
- `Security.allowedEntries`는 Keychain으로만 저장하며 JSON에서는 제외됩니다.
- JSON 저장 시 `completeFileProtectionUntilFirstUserAuthentication` + 권한 `0600` 설정.
- 로드 실패 시 기본값으로 폴백합니다.

# UI / MENU BAR

- `MainTrayMenuContents`:
  - 상태에 따라 "서버 시작/중지" 버튼을 토글
  - 설정 창 열기 / 앱 종료 제공
- `SettingsWindow`:
  - TabView: 일반/프로젝션/보안/기타/플러그인/정보
  - "설정 저장" 버튼에서 `AppSettings.save()` 호출

# UTILITIES

- `NoctilucaLogger(category:)`는 `SiriusLogger`를 앱 번들 ID로 래핑합니다.
- `CInteropHandle`로 C 콜백 컨텍스트 전달/복원 지원.
- `TCCUtil`, `JSON` 등 유틸은 `utils/`에 위치합니다.

# SEE ALSO

- `../SiriusKit/AGENTS.md` - Sirius 프로토콜, 트랜스포트/채널 구조 설명
- `../SiriusKit/SiriusKit/SiriusKit.docc/SiriusKit.md`
- `../NoctilucaClient/` - 클라이언트 앱 구현 (프로토콜 사용 예, UI/연동 흐름)
- `../NoctilucaPluginKit/AGENTS.md` - 플러그인 번들 계약/Info.plist 키 스펙

## Context Resolve Policy

- **반드시** 컨텍스트를 해석/결정할 때 `../SiriusKit`와 `../NoctilucaClient`를 함께 참조할 것.

## Recent Notes

- `CodecOptionsParser.parse(optionsString:)`가 이제 `[CodecOptionKey: CodecOptionValue]` 대신 `CodecOptions`(mandatory/optional, `!required` 지원)을 반환합니다. 기존 호출부는 아직 미정리 상태입니다.
- CodecOption/CodecOptionsParser 정의가 `SiriusKit/channel/msgdef/v1/channels/projection`로 이동했고, 클라이언트에서도 사용할 수 있도록 `public`으로 노출되었습니다.

</section>
<section id="agent-rules">

# AGENT RULES

## 1. Interaction & Language
- 작업을 진행할 때 확실하지 않거나 궁금한 점이 있으면, 되도록 **추측하지 말고 사용자에게 질문**해서 명확히 하는 것을 우선해 주세요.
- 사용자가 한국어 화자인 만큼, 모든 대화와 Plan 작성은 **반드시 한국어**로 진행해 주세요.
- 프로젝트에 대한 중요한 정보나 커다란 변경 사항이 있을 때는, `AGENTS.md`를 수정하여 프로젝트에 대한 최신 정보를 반영해 주세요.

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
