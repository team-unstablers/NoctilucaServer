# PLUGIN PROCESS ISOLATION (플러그인 프로세스 격리 설계 초안)

NoctilucaPluginKit 의 플러그인 번들 로딩 모델을 *in-process dlopen* 에서
*out-of-process XPC service* 로 전환하는 설계 초안입니다.

> **상태**: 초안 (Draft). 구현 착수 전 정렬 단계.
> **브레이킹 체인지 허용**: 현 시점 외부 사용처가 없으므로 호환성 유지 없이 재설계합니다.

## 0. 배경 및 동기

현재 NoctilucaServer 는 플러그인 번들을 자기 프로세스 내에 직접 `dlopen` 하여
사용합니다. 이는 다음의 위험을 갖습니다.

1. **크래시 격리 부재**: 플러그인 코드의 결함이 서버 본체를 죽일 수 있음. 진행
   중이던 세션 / Projection 스트림 / fsaccess 마운트가 모두 영향을 받음.
2. **신뢰 경계 일치 불가**: ClipboardChannel 등 다른 채널에서는 *"인증된 상대가
   공격자"* 위협 모델을 채택하여 빡세게 검증하고 있는데, 플러그인은 native code
   실행권을 가진 *써드파티 코드* 임에도 서버 본체와 같은 메모리 / Keychain /
   네트워크 핸들을 공유함.
3. **ABI 취약성**: Swift dylib 의 ABI 안정성 제약으로 인해 서버 본체 업데이트와
   플러그인 업데이트의 결합도가 높음.

VST / Pro Tools AAX / FxPlug 4 / VSCode extension host 등 동시대 plugin host 의
공통적인 해법인 *별도 프로세스 + IPC* 모델을 채택합니다. macOS native 환경이므로
IPC 는 XPC (`NSXPCConnection`) 를 사용합니다.

## 1. 결정 사항 요약

| 항목 | 결정 |
|---|---|
| 격리 단위 | **Plugin Bundle** (1 bundle = 1 host process). 한 bundle 내 여러 plugin 은 같은 process 에서 공존 |
| Isolation policy | `isolate` (기본) / `no-isolate` (team unstablers Inc., teamid `XHA76UVA95` 서명에 한정) |
| Bundle 설치 위치 | (a) Server bundle 내장 (`Contents/PlugIns/`) (b) `~/Library/Application Support/Noctiluca/Plugins/`. **외부 임의 경로는 미지원** |
| IPC | [Shotoku](../../Shotoku/) (MessagePack over XPC) + `audit_token_t` per-message authorize. Server 내장 `NoctilucaPluginHost.xpc` (XPC service bundle, `_MultipleInstances=YES`) 가 instance 마다 launchd-managed spawn. Bootstrap channel (`HostControlInterface`) + anonymous-endpoint plugin channel (`*Adapter`) 두 단계 (2026-05-17 결정 — §9-A 참조; §4 본문은 stale, T11 에서 재작성 예정) |
| Sandbox | **현재 단계 미적용**. Process 격리만 적용. 향후 capability profile 기반 sandbox 도입 여지는 남겨둠 |
| Lifetime | 모든 host process 는 server 와 lifetime 일치 (idle exit 없음) |
| Manifest | JSON (`NoctilucaPluginSystem/schemas/server-*.json` 스키마) 로 통일. Info.plist 의 메타데이터 필드는 폐기 |
| Manifest 검증 시점 | Spawn **이전**, server 측에서 검증. 동적 capability 변경 불가 |
| 마이그레이션 정책 | 호환성 유지 없이 일괄 재설계 |

## 2. 아키텍처 개요

```
                    ┌──────────────────────────────────────────┐
                    │ NoctilucaServer (main process)           │
                    │                                          │
                    │  PluginRegistry                          │
                    │   ├─ discover() → manifest validation    │
                    │   ├─ codesign / isolation policy check   │
                    │   └─ spawn host processes                │
                    │                                          │
                    │  PluginLoader (abstraction)              │
                    │   ├─ XPCLoader   (default)               │
                    │   └─ InProcessLoader (no-isolate only)   │
                    └─────────────┬────────────────────────────┘
                                  │ NSXPCConnection (per bundle)
                                  ▼
        ┌─────────────────────────────────────────────────────┐
        │ NoctilucaPluginHost.xpc (N instances, 1 per bundle) │
        │   ├─ dlopen(bundlePath)                             │
        │   ├─ Bundle.initialize()                            │
        │   ├─ exports[] → XPC interface 라우팅 등록          │
        │   └─ server callback (logging / config) 호출        │
        └─────────────────────────────────────────────────────┘
```

- Server 의 모든 plugin 관련 코드는 `PluginLoader` 추상화 뒤에 위치하여, 격리/
  비격리 경로가 호출자에게 투명하게 동작.
- `NoctilucaPluginHost.xpc` 는 server bundle 에 내장된 정식 XPC service.
  `ServiceType=Application` + `_MultipleInstances=YES` 로 caller (= server 의 각
  connection) 마다 별도 process instance 가 생성됨.
- Host process 의 본체 로직 (dlopen / manifest 재검증 / dispatch) 은 공유
  dylib 으로 추출하여 host main 은 최소화.

## 3. Plugin Bundle 구조

### 3-1. 디렉토리 레이아웃

```
SamplePluginBundle.bundle/
├── Contents/
│   ├── manifest.json             ← 신규 (JSON schema 준수)
│   ├── Info.plist                ← 표준 bundle 메타데이터만 (CFBundleIdentifier, CFBundleVersion 등)
│   └── MacOS/SamplePluginBundle  ← dylib (principal symbol exported)
```

- `manifest.json` 은 `NoctilucaPluginSystem/schemas/server-*.json` 의
  `NoctilucaPluginBundle` 스키마를 준수합니다.
- 기존 Info.plist 의 plugin 메타데이터 필드 (`NoctilucaPluginID`,
  `NoctilucaPluginExports` 등) 는 전부 manifest.json 으로 이동합니다.

### 3-2. Manifest 필드 추가

기존 스키마에 다음 필드를 추가합니다.

```jsonc
{
  "id": "app.noctiluca.server.bundles.CJKKeyboardHacks",
  "name": "...",
  "isolation": "isolate",   // ← 신규. "isolate" | "no-isolate"
  "exports": [ ... ]
}
```

- `isolation` 의 기본값은 `"isolate"`.
- `"no-isolate"` 선언 시 server 는 spawn 전에 codesign 검증을 수행하고, team
  identifier 가 `XHA76UVA95` 가 아니면 **로드를 거부**합니다 (downgrade 가 아닌
  reject). 의도와 다르게 동작하는 것이 더 위험합니다.

### 3-3. Single-Type 제약 미적용

한 bundle 이 여러 type (`auth_v1`, `rpc_handler_v1`, `keyboard_hack_v1` 등) 의
plugin 을 동시에 export 하는 것을 허용합니다. Bundle 단위 격리이므로 같은 bundle
의 plugin 들은 동일 process 에서 공존하며, bundle 내부 상태 공유가 가능합니다.

## 4. NoctilucaPluginHost.xpc

### 4-1. XPC Service 구성

`NoctilucaServer.app/Contents/XPCServices/NoctilucaPluginHost.xpc/Contents/Info.plist`:

| 키 | 값 |
|---|---|
| `CFBundleIdentifier` | `app.noctiluca.PluginHost` |
| `CFBundlePackageType` | `XPC!` |
| `XPCService.ServiceType` | `Application` |
| `XPCService._MultipleInstances` | `YES` |
| `XPCService.JoinExistingSession` | `YES` |
| `XPCService.RunLoopType` | (TBD: `dispatch_main` 권장) |

### 4-2. XPC Interface 분할

`NoctilucaPluginHost` 가 expose 하는 인터페이스는 두 단계로 분리합니다.

1. **HostControlProtocol** (host lifecycle 관리)
   - `loadBundle(at:replyHandler:)`
   - `unloadBundle(replyHandler:)`
   - `ping(replyHandler:)`
2. **Plugin type 별 service protocol** (`auth_v1` / `rpc_handler_v1` /
   `keyboard_hack_v1`)
   - `loadBundle` 응답에 이 bundle 이 expose 하는 endpoint 들을 함께 반환하거나,
     단일 connection 의 다중 interface 분기 방식으로 처리. 어느 쪽이 깔끔한지는
     구현 단계에서 결정.

### 4-3. Server → Plugin 의 역방향 콜백

`NSXPCConnection` 양방향 인터페이스를 활용합니다.

```swift
connection.remoteObjectInterface = NSXPCInterface(with: HostControlProtocol.self)
connection.exportedInterface     = NSXPCInterface(with: HostCallbackProtocol.self)
connection.exportedObject        = hostCallback
```

`HostCallbackProtocol` 에는 다음과 같은 helper API 를 노출합니다.

- `log(level:message:)`
- `requestUserConsent(prompt:replyHandler:)` (필요 시)
- `readBundleConfig(replyHandler:)`

플러그인이 server 의 내부 자원에 직접 접근하지 않고, 이 좁은 콜백 인터페이스만
통해 통신하도록 강제합니다.

## 5. Isolation Policy 와 Code Signing 검증

### 5-1. 검증 순서

1. Discovery 단계에서 bundle path 발견
2. `manifest.json` 파싱 (JSON schema 검증)
3. Bundle 의 codesign 검증
   - `SecStaticCodeCreateWithPath` → `SecStaticCodeCheckValidityWithErrors`
   - `SecCodeCopySigningInformation` 으로 team identifier 추출
4. `manifest.isolation` 과 team identifier 일관성 검사
   - `"no-isolate"` + team ID `XHA76UVA95` → in-process 로드 허용
   - `"no-isolate"` + 다른 team ID → **reject**
   - `"isolate"` → 어느 team ID 든 XPC 로드
5. PluginLoader 선택 후 spawn / dlopen

### 5-2. 미서명 / 검증 실패

- ad-hoc 서명 또는 검증 실패 bundle 은 일률적으로 reject.
- 디버그 빌드에서의 우회 옵션 (예: 환경 변수) 은 별도 정책으로 결정.

## 6. NoctilucaPluginKit SDK (Plugin 작성자 인터페이스)

Plugin 작성자가 작성하는 코드 형태는 **현 상태를 유지**합니다.

```swift
import NoctilucaPluginKit

public final class CJKKeyboardHacksBundle: NoctilucaPluginBundle {
    public static let id = "app.noctiluca.server.bundles.CJKKeyboardHacks"
    public static let name = ...
    public static let exports: [NoctilucaPluginExport] = [
        .keyboardHack(CJKEmulateWin32HangulToggleHack())
    ]

    public static func initialize() async throws { ... }
    public static func deinitialize() throws { ... }
}
```

SDK 가 추가로 제공하는 것:

1. **manifest.json 자동 생성**: 빌드 타임에 위 메타데이터에서 추출하여
   `manifest.json` 을 생성하는 SPM build plugin 또는 codegen 툴. 이중
   source-of-truth 를 방지합니다.
2. **Principal symbol 컨벤션**: Host process 가 dlopen 후 `NoctilucaPluginBundle`
   타입을 찾기 위한 exported symbol 규약 (예: `_NoctilucaPluginBundleEntry`).
   SDK 매크로 또는 컴파일러 directive 로 자동 생성.
3. **XPC glue layer**: Plugin 작성자는 자신의 코드가 in-process 인지 XPC 너머인지
   알 필요가 없습니다. SDK 가 host process 내에서 export 를 XPC 인터페이스에
   라우팅하는 모든 작업을 담당합니다.

## 7. NoctilucaPluginExport API 의 XPC-portable 재설계

XPC 너머로 안전하게 마샬링하려면 export 의 메소드 시그니처가 다음을 만족해야
합니다.

- 모든 인자 / 리턴 타입이 `NSSecureCoding` 또는 `Codable` 호환 value type
- Reference type 전달 금지 (proxy 필요시 별도 sub-interface 로 분리)
- Closure / Continuation 직접 전달 금지 — XPC reply handler 또는 별도 콜백
  인터페이스로 표현
- `AsyncStream` 등의 streaming API 는 host → server 콜백 인터페이스로 풀어내거나
  `NSXPCConnection` 의 progress reporting 으로 대체

**현 protocol 들을 일괄 재검토해야 합니다.** 특히 다음 셋의 wire shape 가 가장 큰
검토 대상입니다.

| Protocol | 검토 포인트 |
|---|---|
| `AuthPluginV1` | challenge / credential 교환의 round-trip 패턴, 다단계 인증의 state 보존 |
| `KeyboardHackPluginV1` | 키 이벤트 stream 의 양방향 dispatch (host → plugin → host, 동기 응답 latency) |
| `RPCHandlerPluginV1` | 임의 operation payload 의 직렬화 형식 (JSON / Data / Codable generic) |

이 작업이 본 마이그레이션의 가장 큰 단위가 될 것으로 예상합니다.

## 8. Lifecycle 과 Crash Recovery

### 8-1. 정상 lifecycle

- **Server 시작**:
  1. Discovery → manifest 검증 → codesign 검증
  2. 각 isolated bundle 별 host process spawn
  3. `loadBundle(at:)` 호출 → host 가 dlopen + `Bundle.initialize()` 호출
  4. Export endpoint 등록 완료 후 ready
- **Server 종료**:
  1. 모든 host 에 graceful shutdown 신호
  2. Host 가 `Bundle.deinitialize()` 호출 후 종료
  3. Connection invalidation 확인 후 server 종료

### 8-2. Orphan host 방지

Host process 가 server crash 후에도 살아남는 것을 방지하기 위해:

- Host 가 server PID 를 launch arg 로 받음
- `kqueue(EVFILT_PROC, NOTE_EXIT)` 로 server 종료를 감지하여 self-terminate
- 또는 host 가 주기적으로 parent PID 가 1 (launchd) 로 변경되었는지 확인

### 8-3. Host crash 대응

- Server 가 `NSXPCConnection.invalidationHandler` 로 감지
- 정책 (후속 결정):
  - 즉시 respawn 후 `loadBundle` 재시도
  - 또는 해당 plugin 을 *disabled* 마킹 + 사용자 알림
  - `keyboard_hack_v1` 의 경우 fail-safe 로 키 입력 pass-through 폴백

본 초안에서는 *"모두 항상 살아있음"* 기준이므로 respawn-on-crash 가 기본 동작.
N 회 연속 crash 시 disable 전환 등의 정책은 구현 단계에서 결정합니다.

## 9. 작업 순서 (세션 단위)

호환성 유지가 필요 없으므로 한 번에 진행 가능하지만, 검증 가능 단위로 다음과
같이 분할합니다. 각 task 는 **1 세션 (~PR, 4–8시간)** 분량을 목표로 하며,
task 간 의존성을 명시합니다.

### 9-A. 진행 현황 (2026-05-17 기준)

이미 별도 작업으로 완료된 부분:

- [x] **manifest.json 스키마 정의** (§3.2):
  `NoctilucaPluginSystem/schemas/server/pluginkit/v1-draft/20260516.json`.
  `auth_v1` / `keyboard_hack_v1` / `rpc_handler_v1` + `isolationPolicy` 필드 포함.
- [x] **Swift 측 manifest.json 디코딩**:
  `NoctilucaServer/plugins/bundle-system/manifest/v1_draft/` 의 v1-draft
  Codable struct + `NocPluginLocalizableString` / `SoftwareLicenseV1Draft`.
- [x] **`PluginIsolationPolicy` enum + manifest 필드 파싱** (enforcement 는
  T2 에서 완료, loader 분기는 T10 에서).
- [x] **codesign 검증 인프라**:
  `PluginBundleCodeSigningVerifier` (team ID 추출, 서명 유효성 검증),
  `PluginBundleSecurityPolicy` 4단계
  (`disallowAll` / `allowTeamUnstablers` / `allowSigned` / `allowAll`).
- [x] **Discovery**: 앱 번들 `Contents/PlugIns/` + Application Support 스캔.
- [x] **NoctilucaPluginKit protocol metadata 제거**: `name` / `description` /
  `authors` / `license` / `version` / `displayVersion` 모두 manifest.json 으로
  일원화. protocol 에는 `id` + 런타임 capability (`supportedMethods` 등) 만
  남음.

**T2 완료 (2026-05-17)** — isolation policy 교차 검증 + CJKKeyboardHacks manifest 이행:

- [x] `PluginBundleRegistry.loadBundle()` 에 isolation policy 강제 분기 추가.
  `no-isolate` 매니페스트는 team identifier `XHA76UVA95` 의 valid signature
  에만 in-process 로드 허용. 그 외 (서명 없음 / ad-hoc / 다른 team ID) 는
  `manifest.isolationPolicy` 가 `no-isolate` 인 한 거부. 신규 에러 case
  `PluginBundleRegistryError.isolationPolicyViolation` 추가. (커밋 `7a8795a`)
- [x] `CJKKeyboardHacks` 의 메타데이터를 `Contents/Resources/manifest.json`
  으로 이행. `isolationPolicy: "isolate"` 로 선언 (T11 의 XPC 격리 실증에
  대비하여 미리 isolate; T10 까지는 InProcessLoader 폴백). Info.plist 의
  `NOC*` 키 전체 제거. (커밋 `7a8795a`)
- [x] `CJKKeyboardHacksBundle` / `CJKEmulateWin32HangulToggleHack` 의 unused
  stale metadata `static let` (name / description / authors / license /
  version / displayVersion) 제거 — protocol 에서 이미 제거된 필드들의
  caller 정리. (커밋 `7a8795a`)
- [x] 공식 예시 manifest 두 종 (`NoctilucaPluginSystem/examples/server/`
  의 `cjk-assist.json` / `nonke-auth.json`) 의 디코딩 검증 XCTest 추가 —
  `V1DraftManifestDecodingTests`. multi-export / single-export, license
  object form / string form, localized string dict form / 등 wire shape
  variation 을 모두 커버. (커밋 `54e08f5`)
- [x] baseline `81cfb05` 의 protocol metadata 제거에서 stale 해진 caller
  3건 정리 (`Authenticator.swift` 의 `type(of:).name` → `.id`,
  `SoftwareLicenseV1Draft.swift` 의 `@unknown default` 추가,
  `DiagPrinter.swift` 의 누락된 `import NoctilucaPluginKit`). (커밋
  `f2bf0a5`)

스킵 결정:

- [~] **T1 — manifest.json codegen CLI**: 현 시점 스킵. 외부 플러그인 저자가
  늘어나거나 metadata 동기화 부담이 실측되면 재고. 자세한 사유는 §9-B T1 참조.

**Shotoku RPC framework 채택 (2026-05-17)** — XPC 통신 인프라를 자체 구축
(§4 / §7 / §8 의 wire 부분) 하지 않고, 외부 RPC 패키지
[Shotoku](../../Shotoku/) (v0.1.0) 를 도입하기로 결정.

- Shotoku 는 `@RPCInterface` / `@RPCService` / `@RPCProcedure` 매크로 기반
  RPC framework. MessagePack wire, XPC + InProcess 트랜스포트 양쪽 지원,
  `audit_token_t` 기반 per-message authorize (mid-connection send-right
  forwarding 방어 포함), server-streaming / callback closure shape, Codable
  user-error round-trip 까지 모두 v0.1.0 에서 지원.
- 본 결정으로 §4 (NoctilucaPluginHost.xpc) / §7 (XPC-portable 재설계) /
  §8 (Lifecycle 의 wire 부분) 의 인프라 *대부분* 이 Shotoku 로 대체됨. 본
  docs 의 해당 섹션은 일단 그대로 두되, 향후 별도 정리 PR (T11) 에서
  Shotoku 기반으로 재작성 예정.
- **NoctilucaPluginKit (외부 plugin SDK) 자체는 Shotoku 의존성을 갖지
  않음.** 외부 plugin 작성자가 보는 surface 는 깨끗하게 유지. 호스트만
  Shotoku 를 안다. 3-layer 패턴:
    1. **`NoctilucaPluginKit.AuthPluginV1`** — 외부 contract. plugin
       작성자가 보는 surface. Shotoku 미인식.
    2. **`NoctilucaServer 내부 @RPCInterface AuthPluginV1RPC: AuthPluginV1`**
       — host-only wire mirror. parent protocol refinement 으로 시그니처
       drift 를 컴파일 타임에 catch.
    3. **`AuthPluginV1Adapter: AuthPluginV1RPC`** — `any AuthPluginV1`
       instance 를 wrap 하는 thin forwarding class. host 측만 존재.
- 본 결정으로 §9-B 의 T3 ~ T12 가 대폭 단축됨. Shotoku 가 처리하는 부분
  (wire envelope, dispatch, cancellation, callback marshaling, audit token
  검증) 은 모두 본 마이그레이션 범위 밖으로 이동. 자세한 내용은 §9-B 참조.

### 9-B. 남은 작업 (세션 단위)

Shotoku 도입 (§9-A) 으로 의존성 그래프가 다음과 같이 단순화되었습니다.

```
T1 (SKIPPED) — Track A
T2 (DONE)    — Track A
   │
   ▼
T3 (Shotoku 도입 + adapter 패턴 PoC) — Track A
   │
   ├──── T4 (KeyboardHack 적용)   ┐
   ├──── T5 (Auth 적용)           ├── Track B (병렬 가능)
   ├──── T6 (RPCHandler 적용)     ┘
   │
   └──── T7 (NoctilucaPluginHost.xpc)   — Track C (단일 task)
              │
              ▼
            T8 (PluginLoader 추상화 + InProc/XPC 구현)  — Track D
              │
              ▼
            T9 (Registry isolation 분기)                — Track D
              │
              ▼
            T10 (CJK XPC 격리 실증)                     — Track E
              │
              ▼
            T11 (정리 + docs 재작성)                    — Track E
```

#### Track A — Independent / Bootstrap (병렬 진행 가능)

##### ~~T1. manifest.json codegen CLI 도구 (§9.2)~~ — **SKIPPED**
- **상태**: 현 시점 스킵 결정. manifest.json 은 수동 작성으로 충분하다고 판단.
  외부 플러그인 저자가 늘어나거나 metadata 동기화 부담이 실측되면 그 시점에
  재고.
- **(원래 계획)**: JSON Schema 기반 manifest scaffold 생성 CLI
  (`NoctilucaPluginSystem/schemas/` 파싱 → 템플릿 출력, 향후 SPM build plugin
  연결 여지). Swift (`swift-argument-parser`) vs Node.js 중 택일 예정이었음.
- **의존성**: 없음 (다른 task 가 T1 에 의존하지 않으므로 스킵해도 그래프
  영향 없음)

##### ~~T2. isolation policy 교차 검증 + CJKKeyboardHacks manifest 교체 (§9.6 일부 + §9.7 manifest 부분)~~ — **DONE (2026-05-17)**
- **상태**: 완료. 자세한 내용은 §9-A *T2 완료 (2026-05-17)* 섹션 참조.
- **(원래 계획)**: `isolationPolicy == .noIsolate` 시 team identifier
  `XHA76UVA95` 강제 + CJK 번들의 메타데이터를 manifest.json 으로 이동.
- **의존성**: 없음 (T1 없어도 수동 manifest 작성 가능)

##### T3. Shotoku 도입 + adapter 패턴 PoC + `.rpcHandler` case 추가 (2026-05-17 결정 반영)
- **목표**: Shotoku 의존성 추가 + 3-layer adapter 패턴의 PoC 검증 +
  `NoctilucaPluginExport` 의 누락 case 보강.
- **포함**:
  - `NoctilucaServer` 의 SPM dependency 에 Shotoku 추가 (path 또는 git
    URL — Noctiluca 레포 외부의 별도 Swift Package).
  - host-side `*RPC` mirror protocol + `*Adapter` class 의 디렉토리
    컨벤션 결정 (예: `NoctilucaServer/plugins/rpc-adapter/`).
  - **PoC**: 가장 단순한 `KeyboardHackPluginV1` 을 대상으로:
    - `KeyboardHackPluginV1RPC: KeyboardHackPluginV1, Sendable` mirror
      protocol (`@RPCInterface`)
    - `KeyboardHackPluginV1Adapter: KeyboardHackPluginV1RPC` thin
      forwarding class
    - `RPCInProcessFabric` 을 이용한 e2e 검증 (in-process listener +
      client 의 결과가 direct 호출과 일치하는지)
  - `NoctilucaPluginExport.rpcHandler(RPCHandlerPluginV1)` case 추가
    (현재 누락)
- **출력**: PoC 검증 결과 + `*RPC` / `*Adapter` 코드 컨벤션 (네이밍 /
  디렉토리 / 보일러플레이트 단축 여지 — 매크로로 더 줄일 수 있는지 여부).
- **의존성**: T2 완료 전제. 그 외 없음.

#### Track B — 3개 plugin protocol 의 RPC variant + Adapter 적용 (T3 후, 내부 병렬 가능)

각 task 의 공통 패턴:
1. NoctilucaPluginKit 측 protocol 시그니처 정리 (필요시 — 외부 contract
   이므로 최소 변경).
2. host 측 `*RPC` mirror protocol + `*Adapter` class 작성.
3. registry / dispatcher 가 Adapter 경유하도록 갱신.
4. builtin 구현체 (있다면) conformance 검증.

##### T4. KeyboardHackPluginV1 — 본 적용 (T3 의 PoC 를 확정)
- **포함**:
  - `LinuxKeycode` / `KeyboardHackResult` 의 Codable 검증 (enum +
    associated value 자동 derive 확인)
  - `KeyboardHackPluginV1RPC` + `KeyboardHackPluginV1Adapter` 본 적용
  - `HIDIOKeyboardHackRegistry` 가 Adapter 경유하도록 갱신
  - `CJKEmulateWin32HangulToggleHack` (NoctilucaPluginKit 측) 시그니처
    변경 없음 — 외부 contract 유지
- **의존성**: T3

##### T5. AuthPluginV1 — 시그니처 정리 + RPC variant + Adapter + builtin 갱신
- **포함**:
  - 시그니처 정리 (외부 contract 변경 — 필요한 만큼만):
    - `borrowing Data` → `Data` (wire 너머에서 borrow 의미 상실)
    - `: Actor` constraint → `: Sendable` (backing impl 만 actor 로
      유지 가능; protocol 자체는 Sendable 로 약화)
    - `AuthError` 의 `Codable` conform (없으면 추가)
    - `AuthMethod` / `AuthEntry` 의 `Codable & Sendable` 검증
  - `AuthPluginV1RPC` + `AuthPluginV1Adapter` 작성
  - `AuthPluginRegistry` / `Authenticator` 가 Adapter 경유하도록 갱신
  - PAM / SSH / SimplePassword / Null AuthPlugin 의 시그니처 변경 반영
- **의존성**: T3

##### T6. RPCHandlerPluginV1 — protocol→struct 전환 + RPC variant + Adapter + builtin 갱신
- **포함**:
  - `RPCRequest` / `RPCResponse` protocol → `Codable & Sendable` struct
    전환 (Shotoku wire 호환)
  - `request.resolve(with:)` self-reply 패턴 제거 → plugin 이
    `RPCResponse` struct 만 반환
  - `RPCHandlerPluginV1RPC` + `RPCHandlerPluginV1Adapter`
  - `SimpleRPCHandlerRegistry` (또는 해당 dispatcher) 갱신
  - 기존 RPC handler plugin 구현체 (있다면) 갱신
- **의존성**: T3
- **참고**: `NoctilucaServerExtensionV1` 은 본 마이그레이션 범위 밖.
  sketch (`NoctilucaPluginKit/extension/`) 만 보존, 실 구현은 별도 작업
  으로 분리. 양방향 procedure 호출이 본격 필요해지면 Shotoku v0.3 의
  dual-interface 가 도착한 후 다시 검토.

#### Track C — Plugin Host process binary (단일 task)

##### T7. `NoctilucaPluginHost.xpc` (XPC service bundle) + bootstrap/anonymous-endpoint 패턴
- **목표**: 외부 plugin (`.nocbundle`, `isolate=true`) 을 호스팅하는
  sandboxed XPC service bundle. Shotoku `RPCListener` 를 자체 process
  안에서 띄우는 thin entry point.
- **포함**:
  - 신규 타겟: `NoctilucaPluginHost.xpc` (XPC service bundle, App
    bundle 의 `Contents/XPCServices/` 에 embed)
  - Info.plist: `XPCService` dict + `_MultipleInstances = YES`
    (connection 마다 새 instance — launchd 가 lifecycle 관리)
  - 자체 `.entitlements` (App Sandbox + 필요한 capability — T2 의
    codesign 정책과 정합)
  - **2-channel 패턴**:
    1. **Bootstrap channel** (`HostControlInterface` — `loadBundle(path:)`
       / `unloadBundle()` / `ping()`): server 가 mach service name 으로
       connect → launchd 가 새 host instance spawn → server 가
       `loadBundle(path:)` 호출
    2. host 동작: dlopen → `Bundle.initialize()` → plugin instance →
       plugin type 식별 → 해당 `*Adapter` 로 wrap → **anonymous
       `xpc_endpoint_t` 로 second `RPCListener` 띄움** → endpoint 를
       bootstrap reply 로 반환
    3. **Plugin channel** (`*Adapter`): server 가 받은 anonymous
       endpoint 로 second connection → `*RPC` proxy 얻음
  - `authorize:` hook (bootstrap / plugin 양쪽) 에서 parent server 의
    audit token 검증
  - Orphan 방지: launchd 가 처리 (parent app 종료 시 자동 cleanup);
    추가로 `kqueue(EVFILT_PROC, NOTE_EXIT)` 로 parent PID watch 하는
    safety net 검토
- **의존성**: T3 (Adapter pattern 확정 후)
- **참고**: 기존 §9-B 의 T7 (`NoctilucaPluginHost.xpc` + 공유 host
  dylib) + T8 (`HostControlProtocol` + dispatch + `HostCallbackProtocol`)
  의 `.xpc` 타겟 자체는 그대로 살아남았으나, dispatch / callback 부분은
  Shotoku 가 처리하므로 본 단일 T7 으로 통합 + 대폭 축소. Adapter
  framework 분리 (Adapter 코드만 따로 SPM target) 가 필요해지면 본 T7
  진행 중 재고.

#### Track D — Loader 추상화 + Registry 분기

##### T8. `PluginLoader` 추상화 + `InProcessLoader` / `XPCLoader` 구현
- **목표**: `PluginBundleRegistry` 가 isolation policy 에 따라 분기할 수
  있는 loader interface 도입. 두 loader 모두 Shotoku endpoint 차이로
  표현.
- **포함**:
  - `PluginLoader` protocol — `func load(bundle:) async throws ->
    LoadedPluginExports`
  - `InProcessLoader`: `RPCInProcessFabric` 공유 + `.inProcess(id:,
    fabric:)` endpoint. 또는 (perf 위해) builtin path 는 Adapter 우회
    direct 호출 — 본 T8 진행 중 결정.
  - `XPCLoader`: `NoctilucaPluginHost.xpc` 의 mach service name 으로
    bootstrap connect (launchd 가 새 host instance spawn) →
    `HostControlInterface.loadBundle(path:)` 호출 → host 가 반환한
    anonymous `xpc_endpoint_t` 로 second connection → `*RPC` proxy
    반환
  - Loader 반환 type `LoadedPluginExports` 는 `[NoctilucaPluginExport]`
    형태 (외부 surface 그대로 — `any AuthPluginV1` 등)
- **의존성**: T3, T7

##### T9. `PluginBundleRegistry` 의 isolation 기반 loader 분기
- **목표**: T2 의 isolation policy 검증을 통과한 후, 정책에 따라 적절한
  loader 선택.
- **포함**:
  - `PluginBundleRegistry.loadBundle()` 에 `InProcessLoader` vs
    `XPCLoader` 분기
  - `isolationPolicy == .noIsolate` → `InProcessLoader`
  - `isolationPolicy == .isolate` → `XPCLoader`
  - builtin bundle (`NoctilucaCoreAuth`) 은 항상 `InProcessLoader`
- **의존성**: T8

#### Track E — 실증 + 정리

##### T10. CJKKeyboardHacks XPC 격리 실증
- **목표**: 실제 외부 plugin 의 XPC 격리 동작 검증 + 회귀 테스트.
- **포함**:
  - CJKKeyboardHacks 의 manifest `isolationPolicy` (이미 `"isolate"` 로
    T2 에서 선언됨) 가 `XPCLoader` 경로로 로드되는지 확인
  - host process spawn / dlopen / 키 입력 라우팅 동작 확인
  - 한/영 키 입력 정상 동작 회귀 확인
  - latency 측정 (Shotoku XPC round-trip + per-message authorize
    오버헤드)
  - host crash 시 server 정상 동작 + respawn 정책 확인
- **의존성**: T9

##### T11. 정리 + docs 재작성
- **목표**: 마이그레이션 종료 + docs 의 stale 한 부분 (§4 / §7 / §8) 의
  Shotoku 기반 재작성.
- **포함**:
  - 본 docs 의 §4 / §7 / §8 을 Shotoku 기반으로 다시 씀 (현재는 stale
    한 상태로 둠)
  - `PluginBundleRegistry` 의 `@unknown default` switch 등 잔여
    in-process 가정 정리
  - Sketch 로 남아있는 `NoctilucaServerExtensionV1` 관련 파일의 처리
    결정 (보존 / 이동 / 삭제)
  - 외부 plugin 작성자 가이드 docs 작성 (3-layer 패턴 노출 X — plugin
    SDK 만 보이게)
  - AGENTS.md / CLAUDE.md 의 플러그인 섹션 갱신
- **의존성**: T10

## 10. 향후 확장 (현 단계 미적용)

본 초안에서는 단순화를 위해 다음 항목들을 보류합니다. 필요해지는 시점에 추가
설계 단계로 진입합니다.

- **Sandbox profile**: Plugin host 에 대한 capability profile 기반 sandbox 적용.
  Type 별이 아닌 *capability* 별 (`minimal` / `network` / `userData` 등) profile
  로 host service 를 분할하는 방향이 자연스러움. 현 단일 host service 에서 profile
  별 host service 추가는 호환성을 깨지 않는 점진적 변경.
- **Idle exit / lazy spawn**: Auth plugin 처럼 일회성 호출이 많은 plugin 은 idle
  timeout 후 자동 종료, 다음 호출 시 lazy respawn. 본 초안의 *"항상 살아있음"*
  단순화와 trade-off.
- **Plugin 간 통신**: 현재는 명시적으로 금지. 필요해지면 server 가 broker 로
  중계하는 형태로 추가.
- **외부 임의 경로 bundle 지원**: security-scoped bookmark + sandbox 권한 처리
  필요. 현 단계 미지원.
- **Bundle hot reload / 업데이트**: server 재기동 없는 plugin 교체.

## 부록 A. 참조

- `NoctilucaPluginSystem/schemas/server-20260513.json` — manifest JSON schema
- `NoctilucaPluginSystem/src/server/isolation-policy.ts` — isolation policy 정의
- `NoctilucaPluginKit/NoctilucaPluginKit/NoctilucaPlugin.swift` — 현 plugin
  bundle protocol 정의
- `NoctilucaServer/CJKKeyboardHacks/CJKKeyboardHacksBundle.swift` — 실증
  마이그레이션 대상
