<section id="project-info">

# NoctilucaPluginKit

NoctilucaPluginKit은 NoctilucaServer용 **플러그인 번들 인터페이스/계약(API) 정의 모듈**입니다.
외부 플러그인이 서버에 로드될 수 있도록 필요한 프로토콜, 타입, Info.plist 키 스펙을 제공합니다.
서버 쪽의 플러그인 로더(`../NoctilucaServer/plugins/`)와 반드시 함께 맞춰서 변경해야 합니다.

# TECHNOLOGIES USED

- Swift (Foundation, Concurrency)
- Xcode framework target

# DIRECTORY STRUCTURE

- `NoctilucaPluginKit.swift` - PluginKit 버전 타입(`NoctilucaPluginKitVersion`)
- `NoctilucaPluginBundle.swift` - 플러그인 번들 프로토콜(라이프사이클 + exports)
- `NoctilucaPlugin.swift` - 플러그인 타입(`NoctilucaPluginType`), export 래퍼(`NoctilucaPluginExport`)
- `InfoPlistKeys.swift` - 번들/플러그인 Info.plist 키 스펙(NOC* 키)
- `SoftwareLicense.swift` - 라이선스 표현 enum (서버에서 SPDX 문자열로 매핑)
- `auth/`
  - `AuthMethod.swift` - 문자열 기반 인증 방법 정의/확장 포인트
  - `AuthEntry.swift` - 인증 허용 엔트리 (method/identifier/data)
  - `AuthPluginV1.swift` - 인증 플러그인 프로토콜
  - `AuthError.swift` - 인증 오류 타입
- `extensioin/NoctilucaServerExtensionV1.swift` - 서버 확장 플러그인(저레벨 이벤트) **아이디어 스케치**(현재 주석 처리)
- `NoctilucaPluginKit.docc/NoctilucaPluginKit.md` - DocC 스텁
- `NoctilucaPluginKit.xcodeproj` - Xcode 프로젝트

# PLUGIN BUNDLE CONTRACT (HOST SIDE 기준)

서버는 `../NoctilucaServer/plugins/bundle-system/`에서 플러그인 번들을 로드하며,
Info.plist 및 번들 클래스가 아래 조건을 **정확히 충족**해야 합니다.

## 1) 번들 클래스
- 번들의 `principalClass`는 **`NoctilucaPluginBundle`**을 채택해야 합니다.
- 서버는 `Bundle.principalClass`를 통해 로딩합니다.
- 라이프사이클: `initialize()` → `exports` 접근 → `deinitialize()`
- `exports`는 **initialize 이후부터 deinitialize 전까지 변경 금지** (프로토콜 주석 요구사항)

## 2) 번들 Info.plist 필수 키
다음 키들이 존재해야 서버에서 메타데이터 파싱이 성공합니다.

### Core Foundation 키
- `CFBundleIdentifier`
- `CFBundleDisplayName`
- `CFBundleVersion` (UInt32)
- `CFBundleShortVersionString`

### Noctiluca 전용 키 (`InfoPlistKeys.swift`)
- `NOCPluginKitVersion` (UInt32, `NoctilucaPluginKitVersion`)
- `NOCBundleDescription` (String)
- `NOCBundleAuthors` ([String])
- `NOCBundleLicense` (String, SPDX 또는 `CUSTOM:`/`PROPRIETARY:` 접두어)
- `NOCBundleLicenseURL` (String, **선택**; 커스텀/프로프라이어터리 시 권장)
- `NOCBundleExports` ([[String: Any]])

### Export 엔트리 키 (`NOCBundleExports` 내부 딕셔너리)
- `NOCPluginID`
- `NOCPluginDisplayName`
- `NOCPluginType` (`NoctilucaPluginType` rawValue; 현재 `auth`/`feature`/`extension`)
- `NOCPluginDescription`

## 3) 서버 검증 규칙
- `exports` 개수와 Info.plist의 `NOCBundleExports` 개수는 반드시 동일해야 함
- 각 export의 **id/type**가 메타데이터와 1:1 매칭되어야 로딩 성공
- 중복 ID는 로딩 거부
- 보안 정책(`PluginBundleSecurityPolicy`)에 의해 로딩 거부될 수 있음

# AUTH PLUGIN CONTRACT (V1)

## AuthPluginV1 필수 구현
- 정적 메타데이터
  - `id`, `name`, `description`, `authors`, `license`, `version`, `displayVersion`
  - `supportedMethods: Set<AuthMethod>`
- 인스턴스 메서드
  - `allow(_ entry: AuthEntry)` / `deny(_ entry: AuthEntry)`
  - `authenticate(using:payload:) -> Result<uid_t, AuthError>`

## AuthEntry
- `method`: 인증 방식 (`AuthMethod`)
- `identifier`: 추가 데이터 타입 구분자 (예: `bcrypt+sha512`)
- `data`: 인증 데이터(옵션)

## AuthMethod
- 문자열 기반 확장 포인트
- 기본 제공: `.password`, `.sshKey`
- 서버 확장(예시): `.simplePassword`, `.null` (디버그)
- **권장**: 커스텀 인증 방식 ID는 reverse domain 형식 사용

## AuthError
- `unsupportedMethod`, `invalidPayload`, `authenticationFailed`, `unknownError`

# LICENSE METADATA
- `SoftwareLicense` enum으로 표현
- 서버는 SPDX 문자열을 `SoftwareLicense.from(spdxIdentifier:)`로 매핑
- `CUSTOM:` / `PROPRIETARY:` 접두어 사용 시 `NOCBundleLicenseURL` 제공 권장

# SEE ALSO (연동/참조 필수)
- `../NoctilucaServer` - 실제 로더/레지스트리/보안 정책 구현
- `../NoctilucaServer/plugins` - Info.plist 파싱/검증 로직과 보안 정책 (반드시 확인)
- `../SamplePluginBundle` - 플러그인 번들 작성 예시 (샘플)

## Context Resolve Policy
- PluginKit 변경 시 **반드시** `../NoctilucaServer/plugins`와 `../SamplePluginBundle`의 동기화를 고려할 것
- 새로운 플러그인 타입 추가 시 `NoctilucaPluginExport` + 서버 레지스트리/검증 + UI 노출까지 함께 수정 필요

## Recent Notes
- 현재 `NoctilucaPluginExport`는 `.auth`만 제공하며, 다른 타입은 서버 로딩 경로가 없음
- `extensioin/NoctilucaServerExtensionV1.swift`는 **주석 처리된 스케치**로, 실제 구현/ABI 없음
- `SamplePluginBundle/Info.plist`는 **NOC* 키가 아닌 구형 키**를 사용하므로 실제 로더와 불일치 가능성 있음 (참고용)
- **Swift 6 동시성 모델 적합화 (2026-04-17)**:
  - 다음 타입에 `Sendable` 적합성 추가: `NoctilucaPluginKitVersion`, `NoctilucaPluginBundle`,
    `NoctilucaPluginExport`, `AuthPluginV1`, `AuthError`, `NoctilucaServerExtensionV1`, `KeySequence`
  - `AuthError.authenticationFailed`의 associated value 타입을 `Error?` → `(any Error & Sendable)?`로 좁힘
  - `NoctilucaServerExtensionV1.onEvent(...)`의 `payload` 타입을 `Any` → `any Sendable`로 변경
  - 서버/클라이언트의 `@preconcurrency import NoctilucaPluginKit` 사용처는 별도 정리 필요
    (특히 `AuthPluginV1` 구현체가 mutable state를 가질 경우 actor화 또는 `@unchecked Sendable` 처리 필요)

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
