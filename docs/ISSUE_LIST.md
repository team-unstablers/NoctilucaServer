# Critical Issues for First Alpha/Beta Release

첫 테스트 버전 출시를 위해 해결이 시급한 이슈 목록입니다.
우선순위는 **P0(Blocker)** > **P1(Critical)** > **P2(Major)** 순입니다.

## 🚨 P0: Blocker (구동 불가, 크래시, 핵심 기능 불능)
*해결되지 않으면 앱을 정상적으로 사용할 수 없거나, 실행조차 불가능한 항목*

- **#202**: server/ui: 온보딩 경험의 부재 (TCC, 기본적인 필수 설정 등)
- **#201**: server/ui: TCC 관련 상태를 파악하여 설정 화면이나 트레이 아이콘에 표시할 수 있도록 해야 함
- **#228**: refactor(client): ProjectionChannel 동시성(Concurrency) 이슈 해결
- **#209**: client/projection: 프로젝션 종료 / 재시작에 대한 내성이 없음
- **#92**: server/transport: QUIC TLS 설정(tlsUseAutoconf/tlsStrictValidation/identity)이 서버 시작에 반영되지 않음

## 🔴 P1: Critical (기능 동작 불안정, 필수 설정 미반영)
*기능은 동작하지만, 설정이 무시되거나 특정 상황에서 오동작할 수 있는 항목*

- **#225**: client: HIDIO 마우스 입력 처리 전반 리팩토링 필요
- **#90**: server/projection: preferredScreenRecorder 설정이 레코더 선택에 반영되지 않음
- **#91**: server/projection: 코덱 협상 정책 UI가 저장/적용되지 않음
- **#80**: client/input: 마우스/스크롤 입력 설정이 HIDIO에 반영되지 않음
- **#79**: client/input: modifier key override 설정이 HIDIO에 반영되지 않음
- **#155**: server/client-session: 세션 종료 시 채널/리소스 정리 보강
- **#156**: client/ui: 임시 ContentViewModel 정식화 (안정성 관련)

## 🟠 P2: Major (사용성 저하, 예외 처리 미흡)
*테스트는 가능하지만, 문제가 생겼을 때 원인을 알기 어렵거나 불편한 항목*

- **#142**: server/projection: 코덱 협상 실패 시 오류 전파
- **#78**: server: 네고시에이션에 실패하거나 프로젝션 세션 생성에 실패하면 실패 이벤트를 보내야 함
- **#158**: client/logic: 기능 채널 오픈 실패 처리 추가
- **#205**: server/ui: 현재 접속 클라이언트 목록 확인 기능의 부재
- **#152**: server/projection: QualityPlanner 기본값/전략/allow-degradation 설정화

## 🚨 [Codebase Analysis] Additional Critical Risks
*코드베이스 전체 분석 결과 발견된 추가 위험 요소입니다.*

### 1. TCC (권한) 상태 감지 로직 미연동 (Fake UI)
- **위치**: `@NoctilucaServer/ui/onboarding/steps/OnboardingPermissionsStepView.swift`
- **문제**: UI가 `isGranted: false`로 하드코딩되어 있어, 사용자가 권한을 허용해도 UI에 반영되지 않음.
- **영향**: 사용자는 앱이 고장 났다고 오인할 수 있음. `TCCUtil` 연동 필수.

### 2. 마우스 입력 좌표 변환의 복잡성 및 검증 부족
- **위치**: `@NoctilucaServer/feature/hidio/EventInjector+Mouse.swift`
- **문제**: `toX11GlobalCoordinate`, `clampToNearestScreen` 등의 복잡한 좌표 변환 로직이 멀티 모니터/HiDPI 환경에서 오차를 유발할 가능성 높음.
- **영향**: 마우스 커서가 빗나가거나 특정 모니터에 갇히는 현상 발생 가능.

### 3. 세션 종료 및 재접속 시 리소스 누수 (Zombie Resources) (done)
- **위치**: `@NoctilucaServer/client-session/NoctilucaClientSession.swift`
- **문제**: 세션 종료 시 `ProjectionSession`, `SCStream` 등의 리소스가 확실하게 정리(`stop`, `deinit`)되지 않을 위험이 있음.
- **영향**: 재접속 시 화면 송출 실패 또는 서버 리소스 고갈로 인한 멈춤.

### 4. 설정 UI와 실제 동작의 괴리 (Disconnected Settings)
- **위치**: `@NoctilucaServer/ui/views/settings/...` vs `ProjectionSession.swift`
- **문제**: 비트레이트 제한, 코덱 우선순위 등의 설정이 UI에는 존재하지만 실제 `AutoQualityPlanner`나 `CodecNegotiator`에 즉시 반영되지 않음.
- **영향**: 설정을 변경해도 품질이나 동작에 변화가 없어 테스터 혼란 유발.

### 5. 잠금 화면 / 해상도 변경 대응 (Projection Stability) (done)
- **위치**: `@NoctilucaServer/feature/projection/ProjectionSession.swift`
- **문제**: 화면 잠금 시 레코더 전환(SCK -> AVF)이나 모니터 연결/해제 시 인코더 재설정 로직이 불안정할 수 있음.
- **영향**: 모니터 연결/해제 또는 잠금 화면 진입 시 연결이 끊기거나 앱이 크래시될 수 있음.

### 6. 플러그인 보안 정책 검증 로직 미구현 (Security Hole)
- **위치**: `@NoctilucaServer/plugins/bundle-system/PluginBundleRegistry.swift`
- **문제**: 보안 정책(`PluginBundleSecurityPolicy`)은 정의되어 있으나, `loadBundle`에서 이를 검증하는 로직이 주석(`// TODO`)으로만 남아 있음.
- **영향**: 서명되지 않거나 악의적인 플러그인이 로드되어 시스템 보안이 뚫릴 수 있음. (RCE 취약점)

### 7. EventInjector 초기화 실패 시 앱 동작 불능 (Silent Failure)
- **위치**: `@NoctilucaServer/feature/hidio/HIDIOChannel.swift`
- **문제**: `eventInjector.prepare()` 실패 시 로그만 남기고 채널이 계속 유지됨.
- **영향**: 클라이언트는 연결 성공으로 오인하나, 입력이 전혀 작동하지 않음. 오류 전파 필요.

### 8. VTVideoEncoder의 동시성 이슈 및 메인 스레드 블로킹 가능성
- **위치**: `@NoctilucaServer/feature/projection/encoder/VTVideoEncoder.swift`
- **문제**: 인코딩 루프와 설정 변경(비트레이트 조절 등)이 동일한 동기 큐(`workerQueue.sync`)를 사용하여 병목 발생 가능.
- **영향**: 네트워크 상태 변화에 따른 비트레이트 조절 시 화면 송출이 일시적으로 멈추거나 UI 반응성 저하.

### 9. DisplayLayoutManager의 무거운 메인 스레드 작업
- **위치**: `@NoctilucaServer/projection/DisplayLayoutManager.swift`
- **문제**: `updateDisplayLayoutsInner`가 메인 스레드에서 무거운 레이아웃 계산과 시스템 호출을 수행.
- **영향**: 모니터 연결/해제 시 앱 UI가 멈추거나(Beach Ball) 버벅거림.

### 10. 로깅 시스템의 파일 저장 미지원 (Troubleshooting Impossible)
- **위치**: `@NoctilucaServer/utils/NoctilucaLogger.swift`
- **문제**: 로그가 콘솔(OSLog)에만 찍히고 파일로 저장되지 않음. 설정 UI의 파일 로깅 옵션도 미구현.
- **영향**: 베타 테스트 시 사용자로부터 로그를 받아볼 수 없어 원격 디버깅이 사실상 불가능.

### 11. FrameQueue의 무제한 대기 및 데드락 가능성
- **위치**: `@NoctilucaServer/feature/projection/FrameQueue.swift`
- **문제**: `next()` 호출 시 `waiter`가 이미 존재하면 `assert`로 강제 종료됨. 컨슈머가 꼬이면 영구 대기(Deadlock) 발생 가능.
- **영향**: 스트림이 멈추거나, 다중 접속/재접속 시도 시 서버가 비정상 종료됨.

### 12. ConstraintedNSWindowManager의 좀비 윈도우 및 메모리 누수 (done)
- **위치**: `@NoctilucaServer/ui/windows/constrainted/ConstraintedNSWindowManager.swift`
- **문제**: `updateWindows`에서 윈도우를 `close()`만 하고 명시적인 리소스 해제(release) 보장이 불확실함.
- **영향**: 모니터 연결/해제 반복 시 투명 윈도우가 누적되어 시스템 리소스 점유 및 화면 캡쳐 방해.

### 13. 오디오 인코더의 샘플링 레이트 불일치 처리 미흡 (Audio Glitch) (done)
- **위치**: `@NoctilucaServer/feature/projection/encoder/OpusAudioEncoder.swift`
- **문제**: 입력 오디오가 48kHz가 아닐 경우 리샘플링 없이 처리하거나 잘못된 메타데이터로 인코딩함.
- **영향**: 클라이언트에서 피치(Pitch)가 변조되거나(Chipmunk effect), 잡음이 발생함.

### 14. Authenticator의 동기적 검증 및 블로킹 (Auth Blocking) (done)
- **위치**: `@NoctilucaServer/auth/Authenticator.swift`
- **문제**: Bcrypt, PAM 등 고비용 인증 작업이 메인 액터나 이벤트 루프를 블로킹할 가능성이 있음.
- **영향**: 인증 시도 중에는 다른 클라이언트의 화면 전송이나 입력 처리가 일시적으로 멈춤.

### 15. AppSession의 AXObserver 리소스 누수 및 안정성 (done)
- **위치**: `@NoctilucaServer/projection/DesktopContextManager.swift`
- **문제**: `deinit`에서 `AXObserver`를 런루프에서 제거할 때 스레드 컨텍스트 불일치 또는 이미 해제된 객체 접근 위험.
- **영향**: 앱 종료 감지 시점에 `EXC_BAD_ACCESS` 등으로 서버 전체 크래시 발생 가능.
