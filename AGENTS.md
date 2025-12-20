<section id="project-info">

# Noctiluca 

Noctiluca는 macOS 호스트용 원격 제어 솔루션을 제공하는 소프트웨어입니다.

# TECHNOLOGIES USED

- SwiftUI
- AVCaptureSession / ScreenCaptureKit 혼합 사용
- Google Protobuf 3
- QUIC (via Network.framework)

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
