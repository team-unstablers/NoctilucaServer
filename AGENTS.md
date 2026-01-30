<section id="project-info">

# Noctiluca (Monorepo)

Noctiluca는 macOS 호스트 기반 원격 제어 솔루션이며, 이 레포는 서버/클라이언트 앱과
핵심 프로토콜 라이브러리를 함께 관리하는 **monorepo**입니다.

# REPOSITORY LAYOUT (TOP-LEVEL)

- `SiriusKit/` - Sirius 프로토콜/채널/트랜스포트 코어 라이브러리 (server/client 공용)
- `NoctilucaServer/` - macOS 호스트 앱 (세션 수락, 인증, 입력 인젝션, 화면 전송)
- `NoctilucaClient/` - macOS/iOS 클라이언트 앱 (연결/인증, 입력 전송, 화면 수신/디코딩)
- `NoctilucaPluginKit/` - 플러그인 번들 계약/메타데이터 스펙
- `SamplePluginBundle/` - 샘플 플러그인 번들
- `docs/`, `NoctilucaServer.xcworkspace`, `NoctilucaServerTests/` 등

# TECHNOLOGIES USED (CROSS-CUTTING)

- Swift / SwiftUI
- Network.framework (QUIC)
- SwiftProtobuf 3 (Sirius msgdef)
- ScreenCaptureKit + AVFoundation(AVCaptureSession)
- VideoToolbox (H.264/H.265 encode/decode)
- CoreGraphics / CoreMedia
- Security.framework / Keychain
- GameController (클라이언트 입력 디바이스)
- OSLog/콘솔 로깅

# ARCHITECTURE OVERVIEW (CROSS-MODULE)

## 1) Sirius Protocol / Session
- 세션/채널/메시지/트랜스포트 규격은 SiriusKit이 정의합니다.
- MainChannel에서 handshake + 인증을 처리하고, 인증 완료 후 기능 채널을 엽니다.
- 기능 채널은 UUID 기반 feature로 식별됩니다 (예: HIDIO, Projection).

## 2) Transport (QUIC)
- QUIC는 Network.framework 기반 구현이며, ALPN은 `pl.unstabler.sirius`를 사용합니다.
- 기본 포트는 8282입니다 (`SiriusQUICDefaultPort`).

## 3) Projection (Video)
- 서버: ScreenCaptureKit/AVCaptureSession 캡처 → VideoToolbox 인코딩 → ProjectionDataChannel 전송
- 클라이언트: ProjectionDataChannel 수신 → VTDecompressionSession 디코딩 → AVSampleBufferDisplayLayer 렌더링
- 코덱 협상은 Sirius msgdef 기반 옵션을 사용합니다.

## 4) Input (HIDIO)
- 클라이언트에서 HIDIO 채널로 키보드/마우스 이벤트를 전송합니다.
- 서버는 HID 이벤트를 호스트 시스템에 인젝션합니다.

## 5) Auth / Plugin
- 서버는 인증을 플러그인 번들로 확장할 수 있습니다. 기본 인증 번들이 포함되어 있습니다.
- 플러그인 메타데이터는 NoctilucaPluginKit 스펙을 따릅니다.

# COORDINATION & SOURCE OF TRUTH

- 프로토콜/메시지/코덱 옵션과 같은 공용 규격은 SiriusKit이 기준입니다.
- 서버/클라이언트 동시 변경이 필요한 경우, 두 앱의 흐름(핸드셰이크/채널)을 함께 확인하세요.
- 세부 구조는 각 서브프로젝트의 `AGENTS.md`를 우선 참조합니다:
  - `SiriusKit/AGENTS.md`
  - `NoctilucaServer/AGENTS.md`
  - `NoctilucaClient/AGENTS.md`

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
- **권한이 부족하여 작업을 수행할 수 없는 경우, 반드시 사용자에게 elevation 요청을 해야 합니다.** (If a command fails due to insufficient permissions, you must elevate the command to the user for approval.)

## 2. Workflow Protocol (중요)
당신(에이전트)가 OpenAI Codex인 경우, 당신은 기본적으로 자율적(Autonomous)으로 행동하지만, 아래의 **[Explicit Plan Mode]** 조건에 해당할 경우 행동 방식을 변경해야 합니다.

### [Explicit Plan Mode] 트리거 조건
1. 사용자가 명시적으로 **'Plan 모드'**, **'계획 모드'**, 또는 **'설계 먼저'**라고 요청한 경우.
2. 작업이 **3개 이상의 파일**에 구조적 변경을 일으키거나, **Core Logic(Protobuf, Network, AVFoundation)**을 건드리는 위험한 변경일 경우.

### [Explicit Plan Mode] 행동 수칙
위 조건이 발동되면 **즉시 코드 구현을 멈추고** 다음 절차를 따르세요:
1. **Stop:** 코드를 작성하거나 수정하지 마십시오. (파일 읽기는 가능)
2. **Plan:** **한국어**로 상세 구현 계획, 영향 범위, 예상 리스크를 작성하십시오.
   - 계획 작성 전용 도구(예: `update_plan`, `EnterPlanMode` 등)가 있다면 해당 도구를 사용하십시오.
   - 그러한 도구가 없다면, 일반 텍스트로 계획을 작성하여 사용자에게 제시하십시오.
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
