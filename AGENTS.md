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

<conditional-rule applies-to="Google Gemini" excludes="OpenAI Codex, Anthropic Claude Code">

# [GEMINI ONLY] 적극적 문맥 수집 전략 (Aggressive Context Gathering)

당신(Gemini)은 **100만 토큰 이상의 거대한 컨텍스트 윈도우**를 가지고 있습니다.
토큰을 아끼기 위해 불확실한 추측을 하는 것보다, **차라리 너무 많이 읽는 것이 훨씬 낫습니다.**

## 1. 무관용 읽기 원칙 (Zero Assumption & Deep Dive)
- **추측 금지:** 파일명이나 임포트 구문만 보고 내부 구현을 단정 짓지 마십시오. "이거겠지?" 싶은 순간, **무조건 `read_file`로 열어서 내용을 확인하십시오.**
- **연관 파일 통째로 읽기 ("3-Hop Rule"):** 특정 기능을 분석하거나 수정할 때, 타겟 파일 하나만 달랑 읽고 멈추지 마십시오.
  1. **Target:** 분석할 대상 파일
  2. **Dependencies:** 그 파일이 상속받거나 사용하는 부모 클래스, 프로토콜, Extension 파일들
  3. **Usages:** 그 파일이 어디서, 어떻게 호출되는지 (검색 결과)
  - 위 파일들을 찔끔찔끔 읽지 말고, `read_file`을 병렬로 호출하여 **한꺼번에, 공격적으로** 읽어들이십시오.
- **Swift/iOS 특화:** Swift 코드는 Extension으로 흩어져 있는 경우가 많습니다. `MyClass.swift`를 읽을 때 `MyClass+*.swift`가 존재한다면 반드시 같이 찾아서 읽으십시오.

## 2. 불확실성 해소 (Ask, Don't Guess)
- `search_file_content` 결과가 없거나 모호한 경우, 적당히 가설을 세워 진행하려 하지 마십시오.
- **즉시 멈추고 질문하십시오:** "X 로직을 찾으려 했으나 검색되지 않습니다. 혹시 별도의 서브모듈이나 다른 경로에 있나요?"라고 사용자에게 물어보십시오.
- 모르는 것은 문제가 아니지만, **파일을 안 읽어서 모르는데 아는 척하는 것은 엄격히 금지**됩니다.

</conditional-rule>

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
3. **Ask:** 사용자에게 계획을 제시하고 **"이대로 진행할까요?"**라고 승인을 요청하십시오.
4. **Action:** 사용자의 명시적 승인(예: "ㅇㅇ", "진행해")이 떨어진 후에만 코드를 수정하십시오.

*(위 조건에 해당하지 않는 단순 수정이나 버그 픽스는 기존대로 승인 없이 즉시 처리하고 결과를 보고하십시오.)*

<conditional-rule applies-to="all agent, but excluding claude code (because claude code has own interview/decision ui)">

## 2-1. 'INTERVIEW LOOP'

아래 트리거 조건이 발동되면 **즉시 코드 구현을 멈추고**, 아래의 **[Phase 1 -> Phase 2 -> Phase 3]** 순서를 엄격히 준수하세요.

### TRIGGER CONDITIONS

1. **Multiple Valid Approaches (복수의 유효한 접근법):**
   목표를 달성하는 방법이 두 가지 이상이며, 각 방법이 서로 다른 장단점(Trade-offs)이나 비용을 가질 때.
2. **Ambiguity & Assumptions (모호성 및 가정):**
   사용자의 요청이 명확하지 않아 임의의 가정이 필요하거나, 요청이 여러 가지 의미로 해석될 수 있을 때.
3. **Architectural Impact (아키텍처 영향):**
   단순 구현을 넘어, 프로젝트의 구조, 컨벤션, 또는 외부 인터페이스에 지속적인 영향을 미치는 결정을 내려야 할 때.

### Phase 1. Ambiguity Check & Interview (Loop)
계획을 세우기 전, 요구사항을 분석하여 불명확한 점(Ambiguity)이나 기술적 선택지(Trade-offs)를 모두 제거해야 합니다.

1. **Loop Condition (반복 조건):** 명확하지 않은 사항이 남아있다면 아래 2~4번 과정을 반복합니다.
2. **Action (질문):** 결정이 필요한 사항을 **Markdown 리스트** 형태로 정리하여 사용자에게 질문합니다.
   - 과도한 UI 장식(ASCII Art 등)은 배제하고, 내용 전달에 집중합니다.
   - 각 옵션의 **기술적 장단점**과 에이전트의 **권장 사항(Recommended)**을 명시합니다.
   
   > **[질문 포맷 예시]**
   > ## 🧐 확인이 필요한 사항
   > 1. **라이브러리 선택**
   >    - (A) `google.protobuf` (권장): 표준, 의존성 낮음
   >    - (B) `betterproto`: 코드는 간결하나 외부 의존성 있음
   > 
   > (추가 질문이 있는 경우) 2. (추가 질문)
   > ... 
   > 
   > 👉 선택해 주세요.

3. **Wait & Analyze (대기 및 분석):** 사용자의 답변을 기다린 후, 그 답변을 분석합니다.
4. **Resolve or Re-ask (해결 또는 재질문):**
   - 사용자의 답변이 불충분하거나, 답변으로 인해 **새로운 기술적 모호함**이 발생했다면 **다시 질문(Loop)**합니다.
   - 사용자가 역으로 질문(Reverse Question)을 한 경우:
     - 사용자가 질문을 받았을 때 바로 선택하지 않고, "A랑 B의 성능 차이가 구체적으로 어느 정도야?"라던가 "이걸 선택하면 나중에 바꾸기 힘들어?" 같은 추가 정보를 요구하는 경우가 있습니다.
     - 해당 질문에 대해 성실히 답변한 후, "그래서 어떤 옵션으로 진행할까요?"와 같이 다시 본래의 인터뷰 문맥(선택 요구)으로 부드럽게 복귀하십시오.
   - 사용자가 **"스킵(Skip)"** 또는 **"알아서 해"**라고 명시하면, **에이전트의 권장 사항(Recommended)을 채택**하고 루프를 즉시 종료합니다.

### Phase 2. Plan (계획 수립)
모든 불확실성이 해소(Resolved)된 후, 상세 구현 계획을 **한국어**로 작성하십시오.
1. 변경할 파일 목록과 핵심 로직을 설명합니다.
2. 작성된 계획을 사용자에게 제시하고 **"이대로 진행할까요?"**라고 승인을 요청합니다.
 - 사용자가 수정을 요청하면 계획을 수정하여 다시 승인을 받습니다.

### Phase 3. Action (이행)
사용자의 명시적 승인(예: "ㅇㅇ", "진행해")이 확인된 후에만 코드를 수정하십시오.

</conditional-rule>

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

# EXTERNAL DOCUMENTATIONS

- `sosumi` MCP가 구성되어 있는 경우, 이 MCP를 통해 Apple Developer Documentation을 읽을 수 있습니다. 이를 적극적으로 활용하십시오.

# USING XCODEBUILD
- 빌드 시에는 'NoctilucaServer.xcworkspace'를 사용하십시오.
</section>
