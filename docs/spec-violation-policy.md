# SPEC VIOLATION HANDLING POLICY (스펙 위반 처리 정책)

Sirius 프로토콜 구현체(서버 / 클라이언트 / Qt 클라이언트 / libsirius)가 **스펙 위반 메시지를 수신했을 때 어떻게 응답해야 하는지**를 정의합니다.
이 정책은 모든 채널의 수신 검증 경로에 적용됩니다 (MainChannel, ClipboardChannel, TransferChannel, HIDIOChannel, ProjectionChannel/ProjectionDataChannel, 그리고 향후 추가되는 모든 채널).

## 0. 배경 및 동기

본 정책은 다음 두 가지 경험에서 출발합니다.

1. **mstsc.exe 경험 (Ulalaca 시기)**: Noctiluca 이전 프로젝트인 Ulalaca(xrdp 기반 macOS RDP 서버) 개발 당시, freerdp는 사소한 위반에 관용적이었으나 mstsc.exe는 표면적으로 사소해 보이는 위반에도 *"프로토콜 오류로 인해 접속을 종료하였습니다"* 메시지로 즉시 종료하는 경우가 잦았습니다. 클라이언트 개발자 입장에서 *왜* 종료되었는지 알 수 없는 종료 경로는 디버깅 비용을 비대칭적으로 증가시킵니다.
2. **Sirius 프로토콜의 자산**: Sirius는 `ServerNotice` 메시지를 통해 **종료 사유(reason)를 명시적으로 전달**할 수 있도록 설계되어 있습니다. fatal close 시퀀스(ServerNotice → Goodbye → close)는 이미 인프라가 완성되어 있습니다 (커밋 `edf2d3a` `d7d72eb` `3213fea` `076f4eb`).

따라서 Sirius 구현체는 **mstsc의 가장 큰 죄악(이유를 알리지 않은 종료)을 답습하지 않으면서**, 동시에 **DoS 등 보안 위협으로부터 자기 자신을 보호**하는 균형점을 유지해야 합니다.

## 1. 핵심 원칙: Severity-Based Response

전통적인 Postel's Law(*"Be conservative in what you do, be liberal in what you accept"*)는 보안 진영에서 호되게 비판받은 격언이며, 무비판적으로 적용해서는 안 됩니다. 본 프로젝트는 이를 다음과 같이 재해석합니다.

> **"Be conservative in what you do.**
> **Be strict at security boundaries.**
> **Be liberal at ergonomic boundaries.**
> **Always be loud about why."**

스펙 위반은 두 카테고리로 나누어 처리합니다.

### 1-1. Security-Critical Violation → 즉시 종료

다음에 해당하는 위반은 **즉시 채널/세션을 종료**하고, **반드시 `ServerNotice` 또는 그에 상당하는 reason을 동반**합니다.

- **자원 고갈 위협**: 프레임 크기 상한 초과(예: SiriusFrameStreamDecoder 16 MiB cap), `maxInFlightBytes` 초과, 비정상적으로 큰 count(예: representations 1000개 이상)
- **무결성 위반**: 정의되지 않은 opcode, 디코딩 실패, payload length 불일치
- **보안 경계 침범**: path traversal 시도, content injection, 미리 합의되지 않은 feature UUID 요청
- **프로토콜 불변식 위반**: 핸드셰이크 전 feature 메시지 송신, 인증 전 채널 open 시도, 닫힌 채널에 메시지 송신

### 1-2. Ergonomic Violation → 관용 (Warn-and-Recover)

다음에 해당하는 위반은 **즉시 종료하지 않고**, 가능하면 부분적으로라도 의미 있는 동작을 시도합니다.

- **수치 한도 약간 초과**: spec_limit의 1.5배 이내 초과 (송신측 버그일 가능성이 높은 영역)
- **Deprecated 필드 사용**: 현재 메이저 버전에서 deprecated 표시된 필드를 송신측이 채워 보냄
- **Optional 필드 누락**: 신규 도입된 optional 필드가 구버전 송신측에서 누락됨
- **알 수 없는 enum 값**: 향후 버전에서 추가될 가능성이 있는 enum 값

대응 방식: **truncate / drop-the-offending-portion / fallback to default** 중 가장 자연스러운 것을 선택하고, 로그에 warning 레벨로 기록합니다.

### 1-3. Borderline Case

위 두 카테고리에 명확히 분류되지 않는 경우(예: spec_limit 1.5배 ~ N배 사이의 초과)에는 **Pattern A의 임계값 정의로 명시적 line을 그어둡니다**(아래 2-1 참조). 모호한 영역을 코드 곳곳에 산재시키지 않고, 한 곳에 집중하여 관리합니다.

## 2. 적용 패턴

### 2-1. Pattern A — Graceful Minor / Hard Major Threshold

수치 한도(count, size 등)에 대한 위반은 **세 단계의 임계값**으로 정의합니다.

```
spec_limit       = 32                           // mdproto에 명문화된 한도
warn_threshold   = spec_limit * 1.5  = 48      // 이하는 warn + truncate, 계속 처리
hard_threshold   = spec_limit * 32   = 1024    // 이상은 즉시 종료 (의도적 abuse 추정)
```

해석:
- `≤ spec_limit`: 정상.
- `spec_limit < x ≤ warn_threshold`: 송신측 버그 가능성. 로그에 warning 기록 후 spec_limit까지 truncate.
- `warn_threshold < x ≤ hard_threshold`: 회색 지대. 정책에 따라 truncate를 계속할지, 더 강한 신호(예: 채널만 종료, 세션 유지)로 격상할지 결정.
- `> hard_threshold`: 의도적 abuse 추정. 즉시 종료 + ServerNotice.

배수(`1.5x`, `32x`)는 위반 대상의 성격에 따라 조정 가능하나, **두 임계값을 모두 정의하지 않은 채 하나의 임계값만 두는 것은 금지**합니다. 단일 임계값은 mstsc 패턴(*"31개는 OK, 33개는 즉시 종료"*)으로 회귀합니다.

### 2-2. Pattern B — Item-Level Isolation

복합 메시지(repeated 필드, 리스트, 컬렉션 등)에서 일부 항목만 위반된 경우, **메시지 전체를 reject하지 말고 위반된 항목만 drop**합니다.

예시:
- `ClipboardEvent.items`에 3개 item이 있고, 그중 한 item의 `representations`가 spec_limit을 위반
  → 위반된 item만 drop, 나머지 두 item은 정상 처리
  → 사용자는 *"3개 중 2개가 클립보드에 들어감"*이라는 부분 성공 경험을 얻음
- `ClipboardItem.representations`에 5개 representation이 있고, 그중 하나의 inline `data`가 spec(128 KiB) 위반
  → 위반된 representation만 drop, 나머지 4개는 처리
  → 다른 contentType(예: text/plain)으로의 fallback 가능성 유지

이 패턴은 RDP의 RDPDR 호환성 처리에서 *"per-item recovery"*로 알려진 기법이며, *"전부 아니면 전무"* 식 설계의 함정을 회피합니다.

### 2-3. Pattern C — Strict Spec / Lenient Enforcement

**1인 프로젝트(서버/클라이언트 동일 author)** 라는 특수성을 고려한 패턴입니다.

- **mdproto 명문화는 strict하게**: 한도, 불변식, MUST/MUST NOT 표현은 명확히 적습니다.
- **runtime enforcement는 ergonomic하게**: 위 Pattern A/B를 적용하여 사소한 위반은 관용합니다.
- **spec drift 방지**: 본인의 로그가 telemetry 역할을 합니다. *"spec을 어겨도 동작하는 영역"*이 어디인지 로그를 통해 추적하고, 향후 third-party 클라이언트 등장 시 spec 강화 / 한도 상향 중 어느 쪽으로 갈지 데이터 기반으로 결정합니다.

이 패턴이 없으면 *너무 lenient한 enforcement*가 *undocumented quirks*로 굳어져 third-party 호환성 깨짐의 원인이 됩니다.

## 3. ServerNotice 작성 규칙

### 3-1. Reason 필수화

**모든 fatal close 경로에는 ServerNotice가 동반되어야 합니다.** ServerNotice를 보낼 시간/여유가 없는 종료 경로(예: 네트워크 단절 직후)는 별도로 `ABORT` 카테고리로 분류하고, 그 빈도가 정상치를 넘어가면 그것 자체를 버그 신호로 봅니다.

### 3-2. Reason 메시지 작성 가이드

reason 문자열은 **사람이 디버깅 가능한 형태**여야 합니다. *6개월 후의 자기 자신*이 로그만 보고 원인을 파악할 수 있어야 합니다.

- ❌ 나쁜 예: `"protocol error"`, `"invalid message"`, `"limit exceeded"`
- ✅ 좋은 예: `"ClipboardEvent.items count 5234 exceeds hard threshold 1024 (5x spec_limit). Treated as DoS attempt."`
- ✅ 좋은 예: `"TransferDataChunk size 32 MiB exceeds frame cap 16 MiB. See SiriusFrameStreamDecoder."`

길이 자체는 wire 비용이 미미하므로 **충분히 자세히 적습니다**. 디버깅 비용을 reason 문자열 길이로 절약하지 않습니다.

### 3-3. Severity 코드 정밀화

`ServerNoticeCode`는 **세분화하여 정의**합니다. 클라이언트 개발자가 코드만 보고도 *retry해야 할지 / 사용자에게 표시해야 할지 / 무시해야 할지*를 결정할 수 있어야 합니다.

권장 분류:
- `protocolError`: 일반 프로토콜 위반 (디코딩 실패 등)
- `quotaExceeded`: 수치 한도 초과 (Pattern A의 hard threshold)
- `payloadTooLarge`: 단일 페이로드/프레임 크기 초과
- `untrustedContent`: content injection / path traversal 등 보안 게이트 위반
- `policyViolation`: 서버/클라이언트 정책에 의한 거부 (allowFile=false 등)
- `unsupportedOpcode`: 알 수 없는 opcode
- `phaseViolation`: 잘못된 페이즈에서의 메시지 (인증 전 feature 호출 등)
- `internalError`: 구현체 내부 오류 (수신측 책임)

기존 코드를 단일 `protocolError`로 묶어두면 클라이언트 입장에서 적절한 UX 분기(자동 재시도 vs 사용자 통보)를 결정할 수 없습니다.

## 4. 적용 예시 — #261 항목 매핑

본 정책에 따라 #261(protobuf 메시지 크기/개수 상한)의 잔여 4개 항목은 다음과 같이 분류됩니다.

| 위반 유형 | 분류 | 응답 |
|---------|-----|-----|
| Frame > 16 MiB | Security-critical | 즉시 종료 + `ServerNotice(payloadTooLarge, ...)` ✅ 이미 구현 (`687f9ce`) |
| `representations` count: spec=32, soft=48, hard=1024 | Pattern A | 32 초과 시 truncate, 1024 초과 시 종료(`quotaExceeded`) |
| `items` count: spec=1024, soft=1536, hard=32768 | Pattern A | 1024 초과 시 truncate, 32768 초과 시 종료(`quotaExceeded`) |
| `ClipboardData.data` inline > 128 KiB (spec 위반 송신) | Pattern B | 해당 representation만 drop, 다른 representation은 유지 |
| `TransferChannel` `maxInFlightBytes` 초과 | Security-critical | 즉시 종료(`quotaExceeded` 또는 `payloadTooLarge`) |
| `TransferChannel` 무한 스트림 (`totalSize=0`) | 정상 | 종료하지 않음. 환경 조건(fs free space 등)은 구현체(`FileTransferCoordinator` 등) 책임 |
| `TransferStartNotification.totalSize` 초과 수신 | Security-critical | 즉시 종료 ✅ 이미 구현 (`5818f35`, #264) |
| `resolveOmittedData` 누적 버퍼 상한 | Pattern A or Security-critical | maxInFlightBytes 결정 후 자연스럽게 정의됨 |

위 임계값(`32 / 1024`, `1024 / 32768`)은 권장 기본값이며, 실제 적용 시점에 데이터/사용 패턴에 따라 조정 가능합니다. 다만 **Pattern A의 두 임계값을 모두 정의**한다는 원칙은 유지합니다.

## 5. 구현 가이드라인

### 5-1. 검증 코드 작성 시

수신 측 검증 코드를 작성할 때 다음 순서로 점검합니다.

1. **이 위반이 security-critical인가, ergonomic인가?** (1-1 / 1-2 분류)
2. **Pattern A의 임계값(soft / hard)을 정의했는가?** 단일 임계값만 두지 않았는가?
3. **Pattern B로 부분 처리가 가능한 메시지인가?** 그렇다면 위반된 부분만 drop하는 경로를 우선 검토.
4. **fatal close 경로라면 ServerNotice의 code와 reason을 정밀하게 채웠는가?**
5. **로그 레벨이 적절한가?** (warn-and-recover는 warning, fatal close는 error)

### 5-2. mdproto 작성 시

- 한도, 불변식은 RFC-style keyword(MUST / MUST NOT / SHOULD / MAY)로 명확히 적습니다.
- 한도를 적을 때는 **수치를 명시**합니다. *"reasonable size"* 같은 표현은 회피합니다.
- 향후 한도가 변경될 가능성이 있는 경우, 그 가능성을 IMPLEMENTATION NOTES에 적어둡니다.

### 5-3. 신규 채널 추가 시

신규 채널을 도입할 때는 본 정책의 적용 매트릭스(#261 항목 매핑과 같은 표)를 채널의 AGENTS.md 또는 mdproto IMPLEMENTATION NOTES에 작성하고, 어떤 위반을 어떤 카테고리로 처리하는지 명시합니다.

## 6. 회피해야 할 안티패턴

- ❌ **단일 임계값으로만 hard fail 처리** — Pattern A 위반. mstsc로 회귀.
- ❌ **reason 없이 종료** — *"protocol error"* 한 줄짜리 종료는 mstsc의 가장 큰 죄악을 답습.
- ❌ **메시지 전체 reject가 default** — Pattern B를 적용 가능한 곳에서도 일괄 reject. 사용자 경험을 비대칭적으로 깎음.
- ❌ **mdproto에 한도가 없는 채로 runtime에서만 enforcement** — spec drift의 시작.
- ❌ **`protocolError` 단일 코드만 사용** — 클라이언트가 적절한 UX 분기를 못 함.
- ❌ **silently 위반을 무시** — *liberal*과 *silent*는 다릅니다. 모든 위반은 최소한 로그에 기록.

## 7. 정책의 한계 및 향후 검토

본 정책은 다음 가정 하에 작성되었습니다.

- **인증을 통과한 상대방**이 가해자인 시나리오 (ClipboardChannel 보안 감사 보고서의 위협 모델 T1, T2)
- **단일 author** (서버/클라이언트 모두 본인)가 양쪽을 통제 가능한 컨텍스트
- **0.9.x 단계**에서의 spec stability (1.0 이전이라 호환성 부담이 상대적으로 낮음)

향후 다음 변화가 발생하면 정책 재검토가 필요합니다.

- Third-party 클라이언트 등장 → Pattern C의 *"본인 로그가 telemetry"* 가정이 깨짐
- 1.0 릴리즈 이후의 wire 호환성 부담 증가 → Pattern A 임계값을 더 보수적으로 조정 필요
- 인증되지 않은 상대방으로부터의 메시지 수용 시나리오 도입 → security-critical 분류 확대 필요
