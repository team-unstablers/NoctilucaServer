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

- `NoctilucaServerApp.swift`, `AppDelegate.swift` - 앱 엔트리, 메뉴바 UI, 설정 창
- `NoctilucaServer.swift`, `ServerContext.swift` - 서버 싱글턴, SiriusServer 구성/시동, 세션 수락
- `client-session/` - 메인 채널 이벤트 루프, 핸드셰이크/인증, 세션 상태 머신
- `feature/hidio/` - 키보드/마우스 이벤트 인젝션
- `feature/projection/` - 프로젝션 채널/세션, ScreenRecorder(SCK/AVF), VideoEncoder(VT), 코덱 협상
- `projection/` - 디스플레이 레이아웃/컨텍스트 관리
- `auth/` - 인증기, 인증 플러그인 레지스트리, bcrypt/passwd
- `plugins/` - 플러그인 번들 시스템(외부/내장), 기본 인증 플러그인
  - `plugins/bundle-system/` - 번들 메타데이터 파싱/검증, 레지스트리, 보안 정책
  - `plugins/builtins/` - 내장 플러그인 번들 등록 및 메타데이터
  - `plugins/builtins/auth/` - 기본 인증 번들(`NoctilucaCoreAuth`)
- `models/settings/` - `AppSettings` (Application Support + Keychain 저장)
- `ui/` - 메뉴바/설정 UI
- `utils/` - 로깅, JSON, TCC/권한 유틸

# PLUGIN SYSTEM (SERVER SIDE)

## Bundle Loader/Registry
- `PluginBundleRegistry`가 번들 URL에서 `Bundle`을 로드하고 메타데이터(Info.plist)를 파싱합니다.
- 번들 `principalClass`는 `NoctilucaPluginBundle`을 채택해야 하며, `initialize()` 성공 후에만 등록됩니다.
- 메타데이터 검증: **Info.plist의 export 목록 수/ID/타입**이 실제 `exports`와 1:1 매칭되어야 로딩됩니다.
- 등록 시 현재는 `.auth` 타입만 `AuthPluginRegistry`로 라우팅됩니다 (`NoctilucaPluginExport` 스위치).

## Built-in Bundles
- `PluginBundleRegistry.registerBuiltinBundles()`에서 내장 번들을 등록합니다.
- `NoctilucaCoreAuth` 번들은 기본 인증 플러그인을 제공하며,
  - Release: `PAMAuthPlugin`, `SimplePasswordAuthPlugin`
  - Debug: `NullAuthPlugin` 추가

## Info.plist 기반 메타데이터
- `PluginBundlePlistMetadata`/`PluginBundleExportPlistMetadata`가 `NoctilucaPluginKit`의 plist 키 스펙으로 파싱됩니다.
- 라이선스는 SPDX 식별자 문자열을 `SoftwareLicense.from(spdxIdentifier:url:)`로 매핑합니다.
  - `CUSTOM:`/`PROPRIETARY:` 접두어 지원

## Security Policy
- `PluginBundleSecurityPolicy`:
  - `disallowAll` / `allowTeamUnstablers` / `allowSigned` / `allowAll`
- 현재 레지스트리의 실제 정책 검증은 TODO로 남아있고 기본값은 `allowTeamUnstablers`입니다.

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
