# noctilucad 설정 관리 XPC 인터페이스 아키텍처 제안서

## 1. 배경 및 목적

### 현재 상태
NoctilucaServer.app은 서버 역할(QUIC 리스닝, 인증, 세션 관리)과 UI 역할(메뉴바, 설정 창)을 모두 담당하는 단일 프로세스이다. 설정은 `AppSettings`에 통합되어 있으며, JSON 파일과 Keychain에 저장된다.

### 목표
NoctilucaServer를 3개 컴포넌트로 분리하는 아키텍처 전환의 일환으로, **설정 관리의 XPC 인터페이스를 정의**한다.

```
변경 전:  NoctilucaServer.app (서버 + 메뉴바 + 설정 UI)
변경 후:  noctilucad (데몬, 서버) + NoctilucaServer.app (메뉴바 에이전트) + libNoctilucaServerCommon.dylib (공용 모델)
```

보안/네트워크 설정의 변경에는 관리자 인증을 요구하며, macOS 시스템 환경설정의 자물쇠 패턴을 따른다.

---

## 2. 설정 카테고리 분류

설정을 **소유 프로세스** 기준으로 이원화한다.

### 에이전트 소유 (자물쇠 불필요)
에이전트(NoctilucaServer.app)가 직접 읽고 쓴다. XPC 호출 불필요.

| 카테고리 | 주요 필드 | 근거 |
|---------|----------|------|
| General | `autoStart`, `maxConcurrentSessions` | 에이전트의 앱 동작에만 영향 |
| Notifications | `enabled` | UI 알림은 에이전트 책임 |
| Projection | `preferredScreenRecorder`, 코덱 설정 | 프로젝션 파이프라인은 에이전트에서 실행 |
| Logging | `enableFileLogging`, `minimumLogLevel` 등 | 프로세스별 로깅 |
| Telemetry | `enableTelemetry`, `telemetryIdentifier` | 에이전트 텔레메트리 |

**저장 위치**: `~/Library/Application Support/<agent-bundle-id>/settings.json` (기존과 동일)

### 데몬 소유 (자물쇠 필요)
데몬(noctilucad)이 소유한다. 변경 시 Authorization Services 인증을 거쳐 XPC로 요청.

| 카테고리 | 주요 필드 | 근거 |
|---------|----------|------|
| Security | `allowedEntries`, `maxLoginAttempts`, `pluginBundleSecurityPolicy` | 인증 정책은 데몬이 사용 |
| Transport | `implementation`, `motd`, `authChallengeMessage` 등 | QUIC 서버 동작 제어 |
| QUICTransport | `listenPort`, TLS 설정, `identity` | 트랜스포트는 데몬이 관리 |

**저장 위치**: `/Library/Application Support/noctilucad/settings.json` (권한 0600, root:wheel)
**Keychain**: `allowedEntries`는 System Keychain으로 이동 (데몬만 접근)

---

## 3. 자물쇠 동작 흐름

macOS의 Authorization Services + XPC 패턴을 사용한다.

```
[사용자]              [에이전트 (설정 UI)]              [noctilucad]
   |                       |                              |
   |-- 보안 탭 클릭 ------->|                              |
   |                       |-- fetchDaemonSettings() ---->|
   |                       |<-- (현재 설정 JSON) ---------|
   |                       | [설정을 읽기 전용으로 표시]      |
   |                       |                              |
   |-- 자물쇠 클릭 -------->|                              |
   |<-- 시스템 인증 팝업 ----|                              |
   |-- Touch ID / 암호 --->|                              |
   |                       | [AuthorizationRef 획득]       |
   |                       | [편집 UI 활성화]               |
   |                       |                              |
   |-- 포트를 9090으로 ---->|                              |
   |                       | [AuthorizationExternalForm    |
   |                       |  32바이트 생성]                |
   |                       |-- updateTransportSettings(   |
   |                       |     authData, settingsData) ->|
   |                       |                              |-- 인증 데이터 검증
   |                       |                              |-- 설정 저장
   |                       |<-- (성공, 재시작 필요) --------|
   |                       |                              |
   |<- "재시작 필요" 알림 ---|                              |
```

### 커스텀 Authorization Right

```
Right: pl.unstabler.noctiluca.server.settings.modify
Group: admin
Timeout: 300초 (5분간 재인증 불필요)
```

데몬 시동 시 Policy Database에 등록한다. 에이전트는 `SFAuthorizationView`(NSViewRepresentable 래핑)로 자물쇠 UI를 표시하고, 인증 성공 시 `AuthorizationExternalForm`을 XPC 호출에 포함한다. 데몬은 `AuthorizationCreateFromExternalForm` + `AuthorizationCopyRights`로 검증한다.

---

## 4. XPC 인터페이스 설계

### 기존 인터페이스와의 관계

현재 `SiriusXPCProtocol.swift`에 정의된 인터페이스는 **Sirius 프로토콜 트랜스포트 전용**이다:
- `SiriusAgentXPCInterface` (Daemon → Agent): 사전 인증된 클라이언트/스트림 이벤트 전달
- `SiriusDaemonXPCInterface` (Agent → Daemon): announce/depart, 스트림 조작

설정 관리 인터페이스는 **별도의 프로토콜**로 정의하되, 동일한 Mach 서비스 위에서 합성 프로토콜로 결합한다.

### 새로운 XPC 프로토콜

**Agent → Daemon (설정 조회/변경)**

```swift
@objc protocol NoctilucaDaemonSettingsXPCInterface {

    // 설정 조회 (인증 불필요)
    func fetchDaemonSettings(reply: @escaping (NSData?, NSString?) -> Void)
    func fetchDaemonStatus(reply: @escaping (NSData?, NSString?) -> Void)

    // 설정 변경 (authData = AuthorizationExternalForm, 32 bytes)
    func updateSecuritySettings(authData: NSData, settingsData: NSData, reply: @escaping (Bool, NSString?) -> Void)
    func updateTransportSettings(authData: NSData, settingsData: NSData, reply: @escaping (Bool, NSString?) -> Void)

    // 서버 재시작 요청 (포트/TLS 변경 후)
    func requestServerRestart(authData: NSData, reply: @escaping (Bool, NSString?) -> Void)
}
```

**Daemon → Agent (설정 변경 알림)**

```swift
@objc protocol NoctilucaAgentSettingsXPCInterface {
    func daemonSettingsDidChange(_ settingsData: NSData)
}
```

### XPC 커넥션 구조 (합성 프로토콜)

Mach 서비스를 하나로 유지하면서 프로토콜 수준에서 관심사를 분리한다.

```swift
// 데몬 측 export
@objc protocol NoctilucaDaemonCombinedXPCInterface:
    SiriusDaemonXPCInterface,
    NoctilucaDaemonSettingsXPCInterface {}

// 에이전트 측 export
@objc protocol NoctilucaAgentCombinedXPCInterface:
    SiriusAgentXPCInterface,
    NoctilucaAgentSettingsXPCInterface {}
```

`DaemonXPCService.listener(_:shouldAcceptNewConnection:)`에서 `exportedInterface`를 합성 인터페이스로 교체하고, `DaemonXPCHandler`가 두 프로토콜을 모두 준수하도록 확장한다.

---

## 5. 설정 변경의 런타임 반영

일부 설정은 즉시 반영, 일부는 서버 재시작이 필요하다.

| 설정 | 즉시 반영 | 재시작 필요 | 비고 |
|-----|:--------:|:----------:|------|
| `security.allowedEntries` | O | | Authenticator 핫 리로드 |
| `security.maxLoginAttempts` | O | | 다음 인증 시도부터 적용 |
| `security.pluginBundleSecurityPolicy` | | O | 플러그인 재로드 필요 |
| `transport.motd`, `authChallengeMessage` | O | | 다음 핸드셰이크부터 적용 |
| `transport.disableServer...` | O | | 다음 핸드셰이크부터 적용 |
| `quicTransport.listenPort` | | O | QUIC 리스너 재바인딩 |
| `quicTransport.tls*` | | O | TLS 설정은 리스너 재생성 필요 |
| `quicTransport.identity` | | O | 인증서 교체는 리스너 재생성 필요 |

재시작이 필요한 경우, XPC reply에서 `needsRestart` 플래그를 반환하고, 에이전트가 사용자에게 알림을 표시한 후 `requestServerRestart()`를 호출할 수 있다.

---

## 6. AppSettings 호환성 전략

### AppSettings를 Facade로 유지

기존 코드(`NoctilucaServer.swift`, `NoctilucaClientSession+Auth.swift`, 설정 UI 등)가 `settings.security.xxx` 패턴으로 광범위하게 접근하고 있다. `AppSettings` 구조체 자체는 변경하지 않되, `SettingsStore`가 두 영역을 중재한다:

- **Agent 영역**: 기존처럼 `$settings.debounce(0.5s)` → 직접 JSON 저장
- **Daemon 영역**: XPC로 fetch한 결과를 읽기 전용 캐시로 유지, 변경 시 XPC로 위임

```swift
// SettingsStore 수정 개념
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings!
    private var daemonSettingsProxy: DaemonSettingsProxy?

    // Agent 설정만 자동 저장 (debounce)
    // Daemon 설정 변경 시 → daemonSettingsProxy.updateXxx() XPC 호출
}
```

### 과도기 지원

데몬이 완성되기 전에는 `DaemonSettingsProxy`를 "로컬 모드"로 동작시켜 기존처럼 에이전트가 직접 모든 설정을 관리하도록 폴백할 수 있다.

---

## 7. 프로토콜 파일의 위치

| 방안 | 설명 | 장단점 |
|-----|------|--------|
| **A. 파일 공유** | noctilucad와 NoctilucaServer 타겟이 같은 `.swift` 파일을 공유 | 간단하나 두 타겟에 수동 추가 필요 |
| **B. 공유 프레임워크** | `NoctilucaShared` 같은 새 모듈에 배치 | 깔끔하나 새 타겟 추가 비용 |
| **C. SiriusKit에 배치** | 기존 XPC 프로토콜과 동일 위치 | 한 곳 관리, 다만 앱 특화 인터페이스가 범용 라이브러리에 들어감 |

추후 `libNoctilucaServerCommon.dylib`를 만들 계획이 있으므로, 초기에는 **방안 A(파일 공유)**로 시작하고, dylib 분리 시 해당 모듈로 이관하는 것을 권장.

---

## 8. 보안 고려사항

1. **XPC 커넥션 검증**: `listener(_:shouldAcceptNewConnection:)`에서 `auditToken`으로 코드 서명을 확인하여 신뢰할 수 있는 에이전트만 수락
2. **Authorization 타임아웃**: Policy Database에서 `timeout: 300`(5분)으로 설정, 이후 재인증 요구
3. **설정 파일 권한**: `/Library/Application Support/noctilucad/settings.json`은 root:wheel 소유, 0600 권한
4. **Keychain 접근**: `allowedEntries`가 System Keychain에 저장되므로 데몬(root)만 직접 접근, 에이전트는 XPC를 통해서만 접근
5. **App Sandbox 비호환**: Authorization Services는 App Sandbox와 호환되지 않음. 현재 NoctilucaServer.app은 샌드박스 미적용이므로 문제 없음

---

## 9. 주요 결정 사항 요약

| 결정 | 선택 | 대안 | 이유 |
|-----|------|------|------|
| 자물쇠 동작 | Authorization Services + XPC | 앱 재실행 (elevated) | Apple 권장 패턴, 보안적 우수, 매끄러운 UX |
| XPC 서비스 구조 | 기존 Mach 서비스에 합성 프로토콜 | 별도 Mach 서비스 추가 | 관리 단순, launchd plist 추가 불필요 |
| AppSettings 구조 | Facade 유지 (내부만 이원화) | 완전 분리 (AgentSettings + DaemonSettings) | 기존 코드 호환성 극대화 |
| Authorization Right | 커스텀 right 1개 | Security/Transport 별도 right | 초기 단순성 우선, 필요 시 세분화 가능 |
| 프로토콜 파일 위치 | 파일 공유 → dylib 이관 | SiriusKit 배치 | dylib 분리 계획과 일치 |

---

## 10. 참고: 수정 대상 파일

이 아키텍처를 구현할 때 주로 다음 파일들을 수정/추가하게 된다.

**신규**
- 설정 XPC 프로토콜 정의 파일 (에이전트/데몬 공유)
- noctilucad 측 설정 XPC 핸들러
- 에이전트 측 `DaemonSettingsProxy`
- `SFAuthorizationView` SwiftUI 래퍼

**기존 수정**
- `noctilucad/DaemonXPCService.swift` — 합성 프로토콜로 전환
- `NoctilucaServer/models/settings/SettingsStore.swift` — 이원화된 저장/로드
- `NoctilucaServer/ui/views/settings/SecuritySettingsTab.swift` — 자물쇠 UI 추가
- `SiriusKit/.../SiriusXPCProtocol.swift` — NSXPCInterface 팩토리에 새 프로토콜 추가 (또는 별도 팩토리)
