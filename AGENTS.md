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

- **fsaccess byte-range lock (SiriusProtocol 5894e33)** (2026-05-06):
  - mdproto: `wouldBlock=82` 에러코드, `FileSystemMountResponse.supportsLocks`
    capability flag, `LockType` constset (shared/exclusive), 6개 새 메시지
    (`FileSystemLock(Request|Response)` / `Unlock` / `TestLock`, opcode
    0x80C1~0x80C6).
  - SiriusKit msgdef 동기화 완료 (autogen 2 + channel/msgdef 5 파일).
  - exposing peer (NoctilucaClient): macOS 는 `fcntl(F_SETLK)` / `F_GETLK` 로
    OS-level byte-range lock, iOS 는 supportsLocks=false 광고 + 모든 lock op 에
    `notSupported` 응답.
  - consuming peer (NoctilucaServer): `FSAccessMountChannel` 에 sendLock /
    sendUnlock / sendTestLock helper + `FSAccessMountReply.lock|unlock|testLock`,
    mount channel 자체에 `supportsLocks` 1회-set 필드 보관.
  - NFS callback dispatch: `NoctilucaNFSServer.lock / lockTest / unlock` 이
    mount session 의 supportsLocks 에 따라 분기 — true 면 wire 로, false 면
    종전대로 fake success (QuickTime 류 까다로운 NFS client 호환). wire 응답이
    `wouldBlock` 이면 `NFSError.lockDenied` (NFS4ERR_DENIED) 로 변환, navigator
    가 supportsLocks=true 광고했음에도 `notSupported` 를 반환하면 fake success
    로 fallback (warn 로그).
  - share reservation (OPEN deny mode) 매핑은 이번 작업 범위 밖.
- **fsaccess (consuming peer) + nocfsaccessd 데몬 추가** (2026-05-05):
  - 서버 = consuming peer 시나리오. navigator(클라이언트) 가 노출하는 파일을 호스트
    머신의 Finder 에 NFS 마운트로 띄움. fsaccess control / fsaccess_mount channel
    둘 다 host 가 *발신* 측이며, 클라이언트는 이미 exposing peer 로 구현 완료.
  - 신규 top-level SwiftPM 패키지 `NocFSAccessXPC` — host ↔ daemon IPC 인터페이스
    (`NocFSAccessDaemonProtocol` / `NocFSAccessHostProtocol`) 와
    `NSSecureCoding`-conformant DTO 정의. SiriusKit 과 분리되어 데몬은 Sirius
    msgdef 에 의존하지 않음.
  - 신규 타깃 `nocfsaccessd` (NanoNFS 기반 NFSv4 서버 데몬). 가상 트리의
    1단계 connection (`NNNN-username`) / 2단계 mount session 디렉토리 + 정적
    `_README.txt` 까지 데몬 자체에서 응답. mount session 안의 실 파일은
    reverse-XPC 로 host 에 위임.
  - host 앱: `NoctilucaServer/feature/fsaccess/` 와 그 하위 `daemon/`. 13개
    fsaccess_mount send 메서드 + 16개 NFS callback dispatch + spawn / NetFS
    mount lifecycle. `NoctilucaServer.initialize` / `shutdown` 에 wiring.
  - Settings: `AppSettings.FileAccess` (enabled / mountPointPath /
    defaultConsentPolicy) + `FileAccessSettingsTab`.
  - 미완성: NoctilucaClientSession 자동 trigger (인증 완료 후 자동 List/Mount),
    streaming read/write 경로.
  - `docs/nocfsaccessd.md` §2 / §8.2 / §8.3 정정: 본 시나리오에서 host 는
    consuming peer 라는 일관성을 docs 에 반영.
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

# SPEC VIOLATION HANDLING POLICY (요약)

Sirius 프로토콜 구현체가 **스펙 위반 메시지를 수신했을 때 어떻게 응답하는지**를 정의합니다. 모든 채널의 수신 검증 경로에 적용됩니다.

핵심 슬로건:
> *"Be conservative in what you do. Be strict at security boundaries. Be liberal at ergonomic boundaries. Always be loud about why."*

위반은 severity 기준으로 분류합니다:

- **Security-critical** (자원 고갈, 무결성 위반, 보안 경계 침범, 프로토콜 불변식 위반) → **즉시 종료 + `ServerNotice` 동반 필수**.
- **Ergonomic** (수치 한도 약간 초과, deprecated 필드, optional 필드 누락, 미지 enum 등) → **warn-and-recover** (truncate / drop-the-offending-portion / fallback).
- **Borderline** → Pattern A의 3단계 임계값(`spec_limit` / `warn_threshold` / `hard_threshold`)으로 명시적 line 정의. 단일 임계값만 두는 것은 금지(mstsc 패턴으로의 회귀).

상세 규정 — Pattern A/B/C, ServerNotice 작성 규칙, ServerNoticeCode 분류, #261 적용 매트릭스, 안티패턴, 정책 한계 — 는 **[`docs/spec-violation-policy.md`](docs/spec-violation-policy.md)** 를 반드시 참고하십시오. 신규 채널을 도입하거나 수신 검증 로직을 작성할 때는 해당 문서의 *5. 구현 가이드라인* 체크리스트를 따라야 합니다.

</section>
<section id="agent-rules">

# AGENT RULES

## 1. Interaction & Language
- 작업을 진행할 때 확실하지 않거나 궁금한 점이 있으면, 되도록 **추측하지 말고 사용자에게 질문**해서 명확히 하는 것을 우선해 주세요.
- 사용자가 한국어 화자인 만큼, 모든 대화와 Plan 작성은 **반드시 한국어**로 진행해 주세요.
- 프로젝트에 대한 중요한 정보나 커다란 변경 사항이 있을 때는, `AGENTS.md`를 수정하여 프로젝트에 대한 최신 정보를 반영해 주세요.
- **권한이 부족하여 작업을 수행할 수 없는 경우, 반드시 사용자에게 elevation 요청을 해야 합니다.** (If a command fails due to insufficient permissions, you must elevate the command to the user for approval.)

## 2. Workflow Protocol

기본적으로는 자율적으로 행동하되, 아래 경우엔 코드 구현 전에 사용자와 정렬을 맞춥니다:

- **명시적 요청**: 사용자가 'Plan 모드' / '계획 모드' / '설계 먼저'를 요청.
- **위험한 변경**: 3개 이상 파일에 구조적 변경 / Core Logic(Protobuf, Network, AVFoundation) 수정.
- **복수의 접근법**: 유의미하게 다른 trade-off를 가진 선택지가 두 개 이상 존재.
- **모호한 요청**: 사용자 의도가 불분명하거나 가정이 필요.

절차:
1. **질문 도구로 모호함을 해소.** 각 옵션의 trade-off와 권장 사항(Recommended)을 명시. 사용자가 '알아서 해'라고 하면 권장 사항 채택. (Claude Code의 `AskUserQuestion`, Codex CLI / Gemini CLI의 동등 툴 등 환경에서 제공되는 질문 도구를 사용하십시오.)
2. **한국어로 계획(변경 파일 + 핵심 로직 + 영향 범위)을 작성하고 승인 요청.** ("이대로 진행할까요?")
3. **명시적 승인('ㅇㅇ', '진행해' 등) 후에만 코드 수정.**

위 조건에 해당하지 않는 단순 수정/버그 픽스는 절차 없이 바로 진행하고 결과를 보고합니다.

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
