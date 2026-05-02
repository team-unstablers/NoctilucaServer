<section id="project-info">

# Noctiluca (Monorepo)

Noctiluca는 macOS 호스트 기반 원격 제어 솔루션이며, 이 레포는 서버/클라이언트 앱과
핵심 프로토콜 라이브러리를 함께 관리하는 **monorepo**입니다.

# BUILD COMMANDS

## Workspace 사용 (권장)
빌드 시에는 반드시 `NoctilucaServer.xcworkspace`를 사용합니다.

```bash
# 서버 빌드 (macOS)
xcodebuild -workspace NoctilucaServer.xcworkspace -scheme NoctilucaServer -configuration Debug build

# 클라이언트 빌드 (macOS)
xcodebuild -workspace NoctilucaServer.xcworkspace -scheme NoctilucaClient -configuration Debug build

# 클라이언트 빌드 (iOS Simulator)
xcodebuild -workspace NoctilucaServer.xcworkspace -scheme NoctilucaClient -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## XcodeBuildMCP 사용 (에이전트 환경)
XcodeBuildMCP가 구성된 환경에서는 `mcp__XcodeBuildMCP__*` 도구를 우선 사용합니다.
```bash
# 세션 기본값 설정 후 빌드
session-set-defaults → build_sim / build_run_sim
```

# TEST COMMANDS

```bash
# 서버 테스트
xcodebuild -workspace NoctilucaServer.xcworkspace -scheme NoctilucaServerTests -configuration Debug test

# 특정 테스트 클래스 실행
xcodebuild -workspace NoctilucaServer.xcworkspace -scheme NoctilucaServerTests -only-testing:NoctilucaServerTests/AutoQualityPlannerTests test
```

# LINTING

SwiftLint가 `.swiftlint.yml`로 구성되어 있습니다.
```bash
swiftlint lint --config .swiftlint.yml
```

# REPOSITORY LAYOUT (TOP-LEVEL)

- `SiriusKit/` - Sirius 프로토콜/채널/트랜스포트 코어 라이브러리 (server/client 공용, SwiftPM)
- `NoctilucaServer/` - macOS 호스트 앱 (세션 수락, 인증, 입력 인젝션, 화면 전송)
- `NoctilucaClient/` - macOS/iOS 클라이언트 앱 (연결/인증, 입력 전송, 화면 수신/디코딩)
- `NoctilucaPluginKit/` - 플러그인 번들 계약/메타데이터 스펙
- `SamplePluginBundle/` - 샘플 플러그인 번들
- `Gesu/` - Private API 호출용 Swift 매크로 라이브러리 (`@PrivateLibrary`, `#PrivateFunction`)
- `frameworks/` - 외부 xcframework 의존성 (VPX, VPXDecoder)
- `libbcrypt/` - bcrypt 라이브러리 (PAM 인증용)
- `NoctilucaServerTests/` - 서버 테스트
- `docs/`, `distutil/`, `pam.d/` 등 유틸리티
- `NoctilucaClientQt/` - Linux / Windows용 C++/Qt 클라이언트 및 libsirius (SiriusKit의 client-role only C++ 구현체)

# TECHNOLOGIES USED (CROSS-CUTTING)

- Swift / SwiftUI / Swift Concurrency
- Network.framework (QUIC)
- SwiftProtobuf 3 (Sirius msgdef)
- ScreenCaptureKit + AVFoundation (AVCaptureSession, AVAudioEngine)
- VideoToolbox (H.264/H.265 encode/decode), libvpx (VP8 encode/decode)
- AudioToolbox / AVAudioConverter (Opus/G.711 encode/decode)
- CoreGraphics / CoreMedia
- Security.framework / Keychain
- GameController (클라이언트 입력 디바이스)
- OSLog/콘솔 로깅
- Swift Macros (Gesu - Private API 호출)

# ARCHITECTURE OVERVIEW (CROSS-MODULE)

## 1) Sirius Protocol / Session
- 세션/채널/메시지/트랜스포트 규격은 SiriusKit이 정의합니다.
- MainChannel에서 handshake + 인증을 처리하고, 인증 완료 후 기능 채널을 엽니다.
- 기능 채널은 UUID 기반 feature로 식별됩니다 (예: HIDIO, Projection).

## 2) Transport (QUIC)
- QUIC는 Network.framework 기반 구현이며, ALPN은 `pl.unstabler.sirius`를 사용합니다.
- 기본 포트는 8282입니다 (`SiriusQUICDefaultPort`).

## 3) Projection (Video/Audio)
- **비디오**:
  - 서버: ScreenCaptureKit/AVCaptureSession 캡처 → VideoToolbox(H.264/H.265) / libvpx(VP8) 인코딩 → ProjectionDataChannel 전송
  - 클라이언트: ProjectionDataChannel 수신 → VTDecompressionSession / libvpx 디코딩 → MetalVideoRenderer (또는 AVSampleBufferDisplayLayer fallback) 렌더링
  - 지원 코덱: H.264, H.265(HEVC), VP8 (0.9.10 부터. MJPG/ZRLE/WebP 는 0.9.10 에서 제거)
- **오디오**:
  - 서버: ScreenCaptureKit 오디오 캡처 → Opus/G.711 인코딩 → ProjectionDataChannel 전송
  - 클라이언트: ProjectionDataChannel 수신 → AudioDecoder 디코딩 → AVAudioEngine 재생
  - 지원 코덱: Opus, G.711 mu-law/A-law
- 코덱 협상은 Sirius msgdef 기반 옵션을 사용합니다.

## 4) Input (HIDIO)
- 클라이언트에서 HIDIO 채널로 키보드/마우스 이벤트를 전송합니다.
- 서버는 HID 이벤트를 호스트 시스템에 인젝션합니다.

## 5) Auth / Plugin
- 서버는 인증을 플러그인 번들로 확장할 수 있습니다. 기본 인증 번들이 포함되어 있습니다.
- 플러그인 메타데이터는 NoctilucaPluginKit 스펙을 따릅니다.

## 6) AppStream (Experimental)
Microsoft RDP의 RemoteApp에서 영감을 받은 기능으로, 원격 Mac의 개별 앱 윈도우를 로컬 앱처럼 사용할 수 있게 합니다.
이 기능은 영구적으로 **experimental** 상태입니다.

- **프로토콜**: Projection 채널의 `0x80xx` opcode 범위에서 Application Management(appman) 메시지를 정의
  - 앱 목록 조회, 앱 실행/종료, 앱 이벤트 구독, AppStream 시작/종료, 윈도우 이벤트 등
  - 프로토콜 정의: `SiriusProtocol/v1/channels/projection/appman.mdproto.md`
- **일반 Projection과의 차이**: 전체 디스플레이 대신 개별 윈도우 단위로 `ProjectionSession`을 생성하며, 클라이언트는 원격 윈도우마다 네이티브 `NSWindow`를 생성
- **서버**: `ProjectionChannel+appman.swift`에서 요청 처리, `DesktopContextManager`로 윈도우/앱 이벤트 감시, `allowedApps` 보안 정책 적용
- **클라이언트 (macOS only)**: `AppStreamWindowManager`가 윈도우 생성/파괴/업데이트 관리, `AppStreamWindow`(NSWindow 서브클래스)가 각 원격 윈도우를 렌더링
- **Qt 클라이언트**: msgdef 바인딩만 존재, AppStream UI/로직 미구현
- **현재 구현 상태**: 윈도우 스트리밍 기본 동작 구현 완료. 앱 선택 UI, `disableSystemShortcuts` 실제 적용 등 미완성 부분 존재
- **향후 계획**: File System Redirection 등 추가 기능 구현 예정

# COORDINATION & SOURCE OF TRUTH

- 프로토콜/메시지/코덱 옵션과 같은 공용 규격은 SiriusKit이 기준입니다.
- 서버/클라이언트 동시 변경이 필요한 경우, 두 앱의 흐름(핸드셰이크/채널)을 함께 확인하세요.
- 세부 구조는 각 서브프로젝트의 `AGENTS.md`를 우선 참조합니다:
  - `SiriusKit/AGENTS.md` - 프로토콜/채널/트랜스포트 상세
  - `NoctilucaServer/NoctilucaServer/AGENTS.md` - 서버 앱 상세
  - `NoctilucaClient/AGENTS.md` - 클라이언트 앱 상세
  - `NoctilucaPluginKit/AGENTS.md` - 플러그인 계약 상세

## Recent Notes

- **AppStream (Experimental) 윈도우 스트리밍 구현** (서버/클라이언트):
  - 서버: appman 메시지 핸들링, 윈도우 이벤트 구독, allowedApps 보안 정책
  - 클라이언트 (macOS): `AppStreamWindowManager` + `AppStreamWindow`로 원격 윈도우별 네이티브 윈도우 생성
  - 미완성: 앱 선택 UI (현재 Xcode 하드코딩), `disableSystemShortcuts` 미적용
- **오디오 프로젝션 기능 구현 완료 (서버/클라이언트)**:
  - 서버: `AudioEncoder` 프로토콜 및 `OpusAudioEncoder`, `PCMAudioEncoder` 구현
  - 클라이언트: `AudioProjectionSession`, `AudioDecoder` 구현
  - 코덱: Opus, G.711 mu-law/A-law 지원
- **타일링 이미지 코덱 (MJPG / ZRLE / WebP) 제거** (0.9.10): 서버 인코더 / 클라이언트 디코더 / 타일 합성 인프라 (`TileCompositor`, `MetalTileCompositor`, `CPUTileCompositor`, `ProjectionCanvasRenderer`, `MetalProjectionView`) 모두 제거. SiriusKit `CodecFourCC` 의 zrle/mjpg/webp 정의는 wire identifier 보존을 위해 deprecated 주석으로 유지. 대체 코덱은 VP8.
- **NoctilucaClient 디렉토리 리팩토링** (2026-02-01): `core`, `app`, `resources` 분리
- `CodecOptionsParser.parse(optionsString:)`가 이제 `[CodecOptionKey: CodecOptionValue]` 대신 `CodecOptions`(mandatory/optional, `!required` 지원)을 반환합니다.
- CodecOption/CodecOptionsParser 정의가 `SiriusKit/channel/msgdef/v1/channels/projection`로 이동했고, 클라이언트에서도 사용할 수 있도록 `public`으로 노출되었습니다.

</section>
<section id="spec-violation-policy">

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

</section>
<section id="agent-rules">

# AGENT RULES

## 1. Interaction & Language
- 작업을 진행할 때 확실하지 않거나 궁금한 점이 있으면, 되도록 **추측하지 말고 사용자에게 질문**해서 명확히 하는 것을 우선해 주세요.
- 사용자가 한국어 화자인 만큼, 모든 대화와 Plan 작성은 **반드시 한국어**로 진행해 주세요.
- 프로젝트에 대한 중요한 정보나 커다란 변경 사항이 있을 때는, `AGENTS.md`를 수정하여 프로젝트에 대한 최신 정보를 반영해 주세요.
- **권한이 부족하여 작업을 수행할 수 없는 경우, 반드시 사용자에게 elevation 요청을 해야 합니다.** (If a command fails due to insufficient permissions, you must elevate the command to the user for approval.)

## 2. Workflow Protocol (중요)
당신은 기본적으로 자율적(Autonomous)으로 행동하지만, 아래의 **[Explicit Plan Mode]** 조건에 해당할 경우 행동 방식을 변경해야 합니다.

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

- 질문 도구를 사용하여, **모든 불확실성이 해소될 때까지 질문 루프를 수행**하십시오.
- 각 옵션의 **기술적 장단점**과 에이전트의 **권장 사항(Recommended)**을 명시하십시오.
- 사용자가 **"스킵(Skip)"** 또는 **"알아서 해"**라고 명시하면, **에이전트의 권장 사항(Recommended)을 채택**하고 루프를 즉시 종료합니다.

### Phase 2. Plan (계획 수립)
모든 불확실성이 해소(Resolved)된 후, 상세 구현 계획을 **한국어**로 작성하십시오.
1. 변경할 파일 목록과 핵심 로직을 설명합니다.
2. 작성된 계획을 사용자에게 제시하고 **"이대로 진행할까요?"**라고 승인을 요청합니다.
 - 사용자가 수정을 요청하면 계획을 수정하여 다시 승인을 받습니다.

### Phase 3. Action (이행)
사용자의 명시적 승인(예: "ㅇㅇ", "진행해")이 확인된 후에만 코드를 수정하십시오.

## 3. Testing Philosophy (중요)

테스트를 작성하거나 수정할 때는 **'소스 코드에 맞춘 테스트'가 아니라 '명세(spec)와 의도에 맞춘 테스트'**를 작성해야 합니다. 테스트는 현재 구현을 "설명"하는 도구가 아니라, 구현이 올바른지를 "검증"하는 독립적인 기준입니다.

### 기본 원칙
- **명세/의도 우선:** 테스트는 "이 함수/모듈이 *무엇을 해야 하는가*"를 기준으로 작성하십시오. "현재 코드가 *무엇을 하고 있는가*"를 기준으로 작성하지 마십시오.
- **실패해도 정확한 테스트 > 통과하지만 잘못된 테스트:** 올바르게 작성된 테스트가 실패한다면, 그것은 테스트의 문제가 아니라 **구현의 버그를 발견한 것**입니다. 이 경우 테스트를 수정하지 말고, 먼저 사용자에게 보고하고 구현을 고치는 방향으로 진행하십시오.
- **회귀(regression) 방지:** 테스트는 미래에 누군가 의도치 않게 동작을 바꾸었을 때 이를 잡아내기 위한 안전망입니다. 따라서 구현 세부사항이 아니라 **관찰 가능한 동작(observable behavior)**과 **계약(contract)**을 검증해야 합니다.

### 하지 말아야 할 것 (Anti-patterns)
- ❌ 테스트가 실패한다는 이유만으로, 원인을 분석하지 않고 기대값(expected value)을 현재 출력에 맞춰 수정하는 것.
- ❌ 구현의 버그를 그대로 "정답"으로 굳히는 snapshot/golden 테스트를 무비판적으로 갱신하는 것.
- ❌ 테스트를 통과시키기 위해 assertion을 느슨하게 풀거나(`XCTAssertNotNil`로만 때우기 등), 검증 범위를 축소하는 것.
- ❌ 구현의 private 내부 상태나 호출 순서에 과도하게 결합된 테스트를 작성하는 것. (리팩토링만 해도 깨지는 테스트는 나쁜 테스트입니다.)

### 해야 할 것
- ✅ 테스트를 작성하기 전에, 해당 코드가 따라야 할 **명세(프로토콜 스펙, msgdef, 주석, 문서, AGENTS.md 등)**를 먼저 확인하십시오.
- ✅ 명세가 불분명하다면 **INTERVIEW LOOP** 규칙에 따라 사용자에게 질문해서 의도를 명확히 한 뒤 테스트를 작성하십시오.
- ✅ 기존 테스트가 실패했을 때는 다음 순서로 판단하십시오:
  1. **테스트 자체가 명세를 잘못 반영하고 있는가?** → 테스트를 고친다.
  2. **구현에 버그가 있는가?** → 구현을 고친다. (**테스트를 건드리지 않는다.**)
  3. **명세가 바뀌어야 하는가?** → 사용자에게 보고하고 합의한 뒤에 둘 다 고친다.
- ✅ 경계 조건(empty, nil, overflow, 오류 경로 등)을 적극적으로 테스트하십시오. "해피 패스"만 검증하는 테스트는 절반의 가치밖에 없습니다.

### 요약
> **"테스트가 빨간 것은 나쁜 뉴스가 아니라, *지금* 알게 되어 다행인 뉴스다."**
> 테스트를 구현에 맞추지 말고, 구현을 테스트(=명세)에 맞추는 것이 원칙입니다.

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

# OTHER NOTE
- 최대한 예의를 차려서 요청을 드리려 하고 있으나, 너무 바쁘면 가끔씩 반말 메시지가 나가는 경우가 있습니다. 양해 바랍니다.
</section>
