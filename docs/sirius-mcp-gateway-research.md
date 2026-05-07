# Sirius 기반 MCP 게이트웨이 실현 가능성 리서치

**작성일**: 2026-05-05
**목적**: SiriusKit/libsirius 위에 MCP(Model Context Protocol) 게이트웨이를 얹어, AI 에이전트가
원격 macOS 호스트를 제어할 수 있도록 하는 아키텍처의 실현 가능성과 작업량을 평가한다.

---

## 1. 요약 (TL;DR)

- **결론: 충분히 실현 가능하다.** Sirius 프로토콜은 이미 원격 데스크톱에 필요한 전송/인증/멀티채널
  인프라를 제공하며, accessibility / HIDIO / projection / clipboard / transfer / appman 채널이
  AI 에이전트의 perception·action 시나리오 대부분을 커버한다.
- **부족한 부분은 명확하다.** ① accessibility tree가 메뉴바에 한정, ② `DispatchAction`이
  `activate` 한 종류만 지원, ③ 단일 프레임 스크린샷 메시지 부재, ④ MCP 게이트웨이 자체가
  존재하지 않음. 모두 점진적·격리된 작업으로 채울 수 있다.
- **권장 아키텍처**: 별도 프로세스의 **"MCP 게이트웨이"** 가 libsirius(C++) 또는 SiriusKit(Swift)
  위에서 Sirius 클라이언트로 동작하고, 에이전트(Claude/Codex/Cursor 등)에게는 stdio MCP
  transport 로 도구를 노출한다. 게이트웨이 자체는 macOS 외 호스트(Linux/Windows)에서도 실행
  가능하다.
- **외부 생태계 (Anthropic Computer Use, Cua, Bytebot, Fazm, OpenClaw) 와의 정합성**:
  AX-first 조작 모델은 Fazm 과 동일, 차별점은 **원격 transport + 멀티호스트 + production-grade
  인증/멀티채널 인프라**. Anthropic Computer Use 도구 스키마(`computer_20251124`)와 호환되는
  얇은 어댑터를 게이트웨이가 제공하면 즉시 Claude Code 등에 끼워넣을 수 있다. 자세한 비교는
  §10 참조.

---

## 2. 아키텍처

### 2.1 토폴로지

```
+---------------------+   stdio        +-----------------------+   QUIC          +-----------------------+
|   AI Agent          | <===========>  | Sirius MCP Gateway    | <============>  | NoctilucaServer       |
|  (Claude / Codex /  |   MCP JSON-RPC | (libsirius client)    |   Sirius        |  (macOS host)         |
|   Cursor / IDE)     |                |                       |                 |                       |
+---------------------+                +-----------------------+                 +-----------------------+
                                              |
                                              | (도구 호출 → 채널/메시지 매핑)
                                              v
                                       Sirius channels:
                                       - main          (auth, ServerNotice)
                                       - projection    (a11y, dispatch, appman, screenshot*)
                                       - hidio         (raw keyboard/mouse)
                                       - clipboard     (text I/O)
                                       - transfer      (file I/O)
```

### 2.2 게이트웨이의 두 가지 배치 옵션

| 옵션 | 위치 | 장점 | 단점 |
|------|------|------|------|
| **A. 원격 게이트웨이** *(권장)* | Mac이 아닌 별도 머신 (또는 같은 LAN 내 Linux 컨테이너) | 호스트 OS 영향 0. NoctilucaServer 코드를 손대지 않고 외부에서 통합. libsirius(C++) 기반이라 cross-platform. | 네트워크 한 hop 추가 (실측 latency: QUIC 위에서 LAN ~1-3ms, 원격 30-100ms) |
| **B. 호스트 내장 게이트웨이** | NoctilucaServer 와 같은 Mac 내부 (loopback) | latency 최소. AX/SCK 권한 공유 가능 | NoctilucaServer 와 1:1 결합. 보안 경계가 흐려짐. 다중 Mac 관리 안 됨 |

옵션 A가 Sirius의 원래 설계 의도(원격 제어 프로토콜)와 가장 잘 맞고, MCP 도구도 자연스럽게
"여러 원격 Mac을 제어 가능한 어드레스북" 모델로 확장된다.

### 2.3 클라이언트 구현체 선택

- **libsirius (C++)** — `NoctilucaClientQt/dependencies/libsirius/` 에 위치. **Client-only로
  완성**되어 있고 (`결정사항 (2026-02-05)`), Executor 패턴 (`결정사항 (2026-02-19)`) 으로
  스레드 모델이 명확함. Linux/Windows 호스트에서도 동작. **MCP 게이트웨이의 기본 베이스로
  권장.**
- **SiriusKit (Swift)** — Mac 내장 게이트웨이를 만들 경우 사용. Swift Concurrency 친화적이지만
  cross-platform 어려움.

---

## 3. 능력 축 분석

### 3.1 Perception — Accessibility Tree

#### 정의된 메시지 (`SiriusKit/.../msgdef/SiriusProtocol/v1/channels/projection/accessibility.mdproto.md`)

| Opcode | 메시지 | 비고 |
|--------|--------|------|
| `0x8101` | `GetAccessibilityTreeRequest` | nodeId 생략 시 루트 트리 |
| `0x8102` | `GetAccessibilityTreeResponse` | rootNode 반환 |
| `0x8103` | `SubscribeAccessibilityTreeUpdatesRequest` | eventMask + maxDepth 지정 가능 |
| `0x8104` | `SubscribeAccessibilityTreeUpdatesResponse` | subscriptionId 발급 |
| `0x8105` | `UnsubscribeAccessibilityTreeUpdatesRequest` | |
| `0x8106` | `UnsubscribeAccessibilityTreeUpdatesResponse` | |
| `0x8107` | `AccessibilityTreeUpdateEvent` | propertyChanged / childrenChanged / nodeAdded / nodeRemoved |
| `0x8108` | `DispatchActionRequest` | (액션 섹션 참조) |
| `0x8109` | `DispatchActionResponse` | |

`AccessibilityNode` 구조는 `id`, `parentId`, `role` (constset), `hint` (optionset), `bounds`,
`description`, `value`, `attributes`, `metadata`, `children` 으로 LLM이 이해하기에 충분히
구조적이다. `role` 은 `text`, `textField`, `image`, `button`, `toggle`, `slider`, `comboBox`,
`list`, `tab`, `tree`, `domElement`, `layoutContainer`, `window`, `menuItem`, `menuGroup`,
`menu`, `application`, `display`, `session` 등 표준 + reverse-DNS 커스텀 역할 지원.
**프로토콜 자체는 LLM agent 시나리오를 명시적으로 고려해 설계되어 있다** (mdproto 14행:
"LLM-based AI agents to structurally understand and interact with UI elements").

#### 서버 구현의 한계 (`NoctilucaServer/feature/projection/ProjectionChannel+accessibility.swift`)

현재 구현은 **AppStream 세션의 "메뉴바"에 한정**된다.

- `handleGetAccessibilityTreeRequest`(L17–85):
  - `nodeId` 가 있으면 `AppMenuRegistry.shared.element(for:)` 로 캐시된 메뉴 항목만 조회
  - `nodeId` 가 없으면 `state.currentAppStreamSession()` 의 `appSession.snapshotMenuBar(depth: 2)`
    호출 — 메뉴바 루트 한정
- `handleSubscribeAccessibilityTreeUpdatesRequest`(L89–147):
  - `desktopContextManager.subscribeMenuEvents(pid:)` — 메뉴바 변경 이벤트 전용
  - `eventMask` 도 사실상 `childrenChanged` 만 의미를 가짐

#### 부족한 것

1. **일반 윈도우/뷰 트리 빌더**. `AccessibilityTreeBuilder` 자체는 임의 `AXUIElement` 를 받을 수
   있게 만들어져 있으나, 입구가 메뉴바 only.
2. **`AppWindowRegistry` (가칭)** — UUID ↔ AXUIElement 매핑을 윈도우/뷰까지 확장. 현재
   `AppMenuRegistry` 의 패턴 (CFEqual 기반 UUID 재사용) 을 그대로 따르면 된다.
3. **루트 분기 확장** — `nodeId` 생략 시 "활성 디스플레이 → 모든 윈도우 → 포커스된 앱의 윈도우
   순으로 트리 구성" 같은 정책. macOS 의 시스템 와이드 AX 스냅샷은 매우 무거우므로 깊이/필터
   정책이 필수.
4. **`includeSnapshots` 플래그 구현** — `GetAccessibilityTreeRequestFlags.includeSnapshots`
   는 정의만 되어 있고 미구현. 노드별 비트맵을 LLM에게 전달 가능하면 vision 모델과 결합 시
   탁월함.

#### 보완 위치

- `ProjectionChannel+accessibility.swift` 의 두 핸들러
- 신규: `NoctilucaServer/projection/AppWindowRegistry.swift` 또는 `DesktopContextManager`
  내부의 별도 캐시
- `AccessibilityTreeBuilder.swift` 는 거의 그대로 활용

---

### 3.2 UI Action — DispatchAction

#### 프로토콜 정의 (`accessibility.mdproto.md` `AccessibilityActionType`)

`activate`, `deactivate`, `contextMenu`, `click`, `doubleClick`, `longClick`, `focus`,
`blurFocus`, `scroll` (deltaX/deltaY), `expand`, `collapse`, `setValue` (textValue/intValue/
boolValue/floatValue) — 12종.

#### 서버 구현 (`ProjectionChannel+accessibility.swift:167-208`)

```swift
guard request.actionType == .activate else {
    // ... errorMessage: "Unsupported actionType: \(request.actionType.rawValue)"
}
let axResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
```

**`activate` 만 구현. 나머지 11종은 모두 에러.**

#### 보완 매핑 (AX 기반)

| ActionType | 구현 경로 |
|-----------|-----------|
| `activate` / `click` | `AXUIElementPerformAction(element, kAXPressAction)` *(현재 구현)* |
| `deactivate` | `kAXDecrementAction` 또는 toggle 의 경우 `AXUIElementSetAttributeValue(kAXValueAttribute, false)` |
| `contextMenu` | `kAXShowMenuAction` |
| `doubleClick` / `longClick` | AX 직접 액션 없음 → `bounds` 중심 좌표로 `CGEvent` 더블클릭 합성 (HIDIO 경로 재사용 가능) |
| `focus` | `AXUIElementSetAttributeValue(element, kAXFocusedAttribute, true)` |
| `blurFocus` | 같은 속성 false. 일부 앱은 무시함 |
| `scroll` | element bounds 위로 `CGEvent` scroll 합성 (또는 `kAXScrollToVisibleAction`) |
| `expand` / `collapse` | `kAXShowMenuAction` 변종 또는 `AXUIElementSetAttributeValue(kAXDisclosingAttribute, true/false)` |
| `setValue` | `AXUIElementSetAttributeValue(element, kAXValueAttribute, ...)` — text/bool/int/float 분기 |

#### 보완 위치

- `ProjectionChannel+accessibility.swift:167` 의 `handleDispatchActionRequest` switch 확장
- AX 속성 조작 유틸: `NoctilucaServer/projection/` 또는 `feature/projection/accessibility/`
  하위 신규 파일 권장 (`AccessibilityActionDispatcher.swift` 가칭)

---

### 3.3 Raw HID Input — HIDIO

#### 프로토콜

`HIDIOPacket.events` (oneof) — `RawEvent`, `KeyboardSetupEvent`, `KeyboardEvent`,
`MouseMoveEvent`, `MouseButtonEvent`, `MouseWheelEvent`, `PenSetupEvent`, `PenDestroyEvent`,
`PenProximityEvent`, `PenMoveEvent`, `PenButtonEvent`, `TouchEvent` 12종.

`KeyboardEvent.eventType` 에 **`ucs4`** 가 있다. 이 모드에서는 `keyCode` 필드에 유니코드
코드포인트를 직접 담을 수 있어 **한글/CJK/이모지 등 모든 텍스트 입력에 별도 키 매핑 유틸이
필요 없다.** MCP 도구의 `input.type_text(text: string)` 구현에 매우 유리하다.

#### 서버 구현 (`HIDIOChannel.swift`)

- 구현 완료: `KeyboardEvent` (keyDown/keyUp/ucs4), `MouseMoveEvent`, `MouseButtonEvent`,
  `MouseWheelEvent`, `KeyboardSetupEvent` (hack 등록).
- 미구현: `RawEvent` (의도적 미구현, `// not implemented`), Pen 5종, `TouchEvent` —
  `default: break`. **MCP 시나리오에서는 불필요.**
- 마우스 좌표계: `EventInjector+Mouse.swift` 가 `absolute+percent`, `relative+pixel`,
  `relative+percent` 모두 지원. 디스플레이 레이아웃 정보(`displayman`)와 결합 시 다중 모니터
  환경도 처리 가능.

#### 클라이언트 송신 측 (`NoctilucaClient/core/feature/hidio/`)

- `HIDIOChannel.swift` 가 `HIDIOPacket` 조립
- `HIDIOVirtualDevice.swift` 가 NSEvent 등을 패킷으로 변환

libsirius(C++) 측은 `include/libsirius/feature/hidio/LinuxKeycode.hpp` 에 키코드 상수가 있어
게이트웨이가 이를 그대로 사용 가능.

#### 부족한 것

- **없음.** MCP 도구(`input.send_keys`, `input.type_text`, `input.mouse_*`) 매핑에 충분.

---

### 3.4 가상 스크린샷 (현재 미정의 — 신규 정의 필요)

#### 현재 상황

- ProjectionDataChannel 은 **라이브 비디오 스트림** (H.264/H.265/VP8) 전용. MCP 에이전트는
  단발성 호출(stateless)을 선호하므로 stream을 켜는 비용은 부적절.
- `AccessibilityNodeSnapshot` (mdproto L228) 은 노드 단위 비트맵. 화면 전체를 커버하지 못함.
- **단일 프레임 스냅샷 메시지는 정의되어 있지 않다.**

#### 제안 메시지

`SiriusProtocol/v1/channels/projection/screen_capture.mdproto.md` (가칭) 신규 추가:

```protobuf
/// Requests a one-shot screen capture (PNG or JPEG).
// @opcode: 0x800A
message CaptureScreenRequest {
    uint64 requestId = 1;

    /// Display ID to capture. If 0 or omitted, the active/primary display is used.
    optional uint32 displayId = 2;

    /// Optional clip region (in pixels, top-left origin).
    optional SRRect clipRect = 3;

    /// Preferred MIME type. Server may downgrade.
    /// e.g., "image/png", "image/jpeg", "image/webp"
    string preferredMimeType = 4;

    /// JPEG/WebP quality (0-100). Ignored for PNG.
    optional uint32 quality = 5;

    /// Maximum longer-edge in pixels. 0 = no scaling.
    optional uint32 maxDimension = 6;
}

/// Response to CaptureScreenRequest.
// @opcode: 0x800B
message CaptureScreenResponse {
    uint64 requestId = 1;
    bool success = 2;
    optional string errorMessage = 3;

    /// Actual MIME type of the returned image.
    string mimeType = 4;
    /// Image bytes.
    bytes data = 5;
    /// Captured pixel dimensions.
    uint32 width = 6;
    uint32 height = 7;
    /// Wall-clock capture time (epoch milliseconds).
    uint64 capturedAtMs = 8;
}
```

#### Opcode 할당 후보

projection 채널 (0x80xx) 의 빈 영역:

- `0x800A`–`0x8020` (17개) — **`0x800A`/`0x800B` 권장**
- `0x8025`–`0x8040` (28개)
- `0x804A`–`0x8060` (23개)
- `0x8083`–`0x80BF` (61개)

#### 서버 구현

`ScreenCaptureKitScreenRecorder` 또는 `AVFoundationScreenRecorder` 를 일회성으로 호출해
`CGImage` → `NSBitmapImageRep` → PNG/JPEG/WebP 인코딩. 이미 비슷한 일회성 캡처 코드가 다른
경로에 있을 수 있으므로 `recorder/` 또는 `projection/` 하위에 `OneShotScreenCapturer.swift`
같은 신규 유틸로 분리 권장.

#### 비용 / 권한

- 비용: SCK 의 streaming session을 띄우지 않고 `CGWindowListCreateImage` 또는
  `CGDisplayCreateImage` 만 사용해도 충분. macOS 14+ 에서는 `SCScreenshotManager` 가 가장
  자연스러움.
- 권한: NoctilucaServer 가 이미 ScreenCaptureKit 권한을 보유 — 추가 TCC 다이얼로그 없음.

---

## 4. 인증 / 보안

### 4.1 자동화에 적합한 인증 메서드

| 플러그인 | method 문자열 | 적합도 |
|---------|---------------|--------|
| `NullAuthPlugin` | `none` | **부적합** — `#if DEBUG` 가드. Release 빌드 미포함 |
| `SimplePasswordAuthPlugin` | `simple-password` | **권장** — payload=raw password bytes. 서버에서 sha512+bcrypt 검증 |
| `PAMAuthPlugin` | `password` (PAM 컨벤션) | 가능 — 단, 시스템 사용자와 동일 자격 |

MCP 게이트웨이는 환경변수 또는 OS keychain (macOS Keychain / libsecret / Windows Credential
Manager — libsirius 가 이미 추상화) 에 패스워드를 저장하고, `AuthRequest.payload` 로 전송.

### 4.2 인증 흐름 (libsirius 클라이언트 기준)

1. `SiriusClient(executor).run()` → `connect()` → MainChannel 생성
2. `sendClientHello(.v1_0, agentName: "NoctilucaMCP/0.1")`
3. `ServerHello` 수신 → `AuthChallenge` 수신
4. `sendAuthRequest(method: "simple-password", nonce: challenge.nonce, payload: pwBytes)`
5. `AuthResponse(sessionId)` 수신 → 채널 오픈 가능

opcode: `ClientHello 0x0010`, `ServerHello 0x0011`, `AuthChallenge 0x0014`,
`AuthRequest 0x0012`, `AuthResponse 0x0013` (MDProto `general.mdproto` 기준).

### 4.3 보안 고려사항

- **에이전트 = 사용자 권한 등가물**. AX 와 HIDIO 는 사실상 풀 컨트롤이므로 게이트웨이 자격이
  유출되면 호스트 전체가 노출된다. 게이트웨이 프로세스의 자격 저장소를 강하게 보호할 것.
- **Scope policy**. 서버 측에 "이 인증 토큰은 accessibility/HIDIO만 허용, 파일 전송은 금지"
  같은 capability scope 가 현재 없다. MCP 시나리오를 감안해 추가 검토 필요. 단기적으로는
  기존 `AppSettings.security.allowedEntries` (Keychain) 의 사용자 단위 제어로 충분.
- **`disableSystemShortcuts`** (AppStream 옵션) 미적용 상태 — 에이전트가 `cmd+q` 등을
  시스템 단축키로 처리하면 호스트 자체가 종료될 수 있음.
- **Audit 로깅**. 에이전트가 수행한 모든 액션을 NoctilucaServer 측에서 기록할 수 있도록
  `DispatchActionRequest` 와 `HIDIOPacket` 송신 로그를 명시적으로 남기는 것을 권장.

---

## 5. 보조 채널 (활용 가능)

### 5.1 AppMan (`projection/appman.mdproto.md`)

| Opcode | 메시지 | 용도 |
|--------|--------|------|
| `0x80E1` / `0x80E2` | `ApplicationListRequest` / `Response` | 설치/실행 중 앱 목록 |
| `0x80E3` / `0x80E4` | `ApplicationLaunchRequest` / `Response` | 특정 앱 실행 |
| `0x80E5` / `0x80E6` | `ApplicationTerminateRequest` / `Response` | 종료 |
| `0x80E7`+ | 앱/윈도우 이벤트 | open/close/focus 등 |

서버 구현: `ProjectionChannel+appman.swift` 에 `handleApplicationListRequest` 등 존재.
`AppSettings.allowedApps` 정책 적용. **MCP 도구 `apps.list`, `apps.launch`, `apps.terminate`
에 그대로 매핑 가능.**

### 5.2 Clipboard

`SubscribeClipboardRequest 0x8001` / `ClipboardEvent 0x8005` / `GetClipboardRequest 0x8006`.
서버 구현: `feature/clipboard/ClipboardChannel.swift`. 텍스트(`text/plain`) I/O가 즉시 가능.

**MCP 시나리오에서의 가치:**
- 에이전트가 긴 텍스트를 텍스트필드에 직접 타이핑하지 않고, 클립보드에 넣고 `cmd+v` 로
  붙여넣기 — 훨씬 빠르고 안정적.
- 호스트에서 선택된 텍스트를 에이전트에게 readback.

### 5.3 File Transfer

`TransferStartNotification 0x8001` / `TransferDataChunk 0x8002`. 청크 기반 단방향 전송.
`feature/transfer/TransferChannel.swift` 구현됨.

**MCP 도구 `files.read_remote(path)`, `files.write_remote(path, bytes)` 매핑 가능.**
단, 와이어상의 path 는 opaque 가상 경로 (`/noctiluca/clipboard/file/{UUID}`) 를 사용하는
보안 정책이 있으므로 (`NoctilucaClientQt/CLAUDE.md` 의 "Linux clipboard file transfer 경로"
참조), MCP 용으로는 별도의 가상 경로 네임스페이스 (`/noctiluca/mcp/{UUID}`) 를 두는 것이
권장된다.

### 5.4 (선택) NocFSAccessd

최근 커밋(`9f74686`, `1d3ecd0`)으로 **`nocfsaccessd`** 라는 데몬이 추가되고 있다 — XPC 기반
파일 시스템 접근. MCP 시나리오와 직접 연관은 없으나, 향후 "에이전트가 호스트 파일 시스템을
읽기/쓰기" 시나리오에 사용될 가능성.

---

## 6. MCP 도구 매핑 제안

게이트웨이가 MCP server 로서 AI 에이전트에 노출하는 도구 카탈로그(예시).

| MCP Tool | Sirius 채널 | 메시지 | 비고 |
|---------|------------|--------|------|
| `screen.capture` | projection | `CaptureScreenRequest 0x800A` | **신규 메시지 필요** |
| `screen.list_displays` | projection | `displayman` (`0x8041`+) | 기존 |
| `a11y.get_tree` | projection | `GetAccessibilityTreeRequest 0x8101` | **루트 확장 필요** |
| `a11y.subscribe` | projection | `SubscribeAccessibilityTreeUpdatesRequest 0x8103` | **윈도우 트리 확장 필요** |
| `a11y.dispatch_action` | projection | `DispatchActionRequest 0x8108` | **action types 확장 필요** |
| `input.send_keys` | hidio | `KeyboardEvent` (keyDown/keyUp) | 기존 |
| `input.type_text` | hidio | `KeyboardEvent` (ucs4) | 기존, CJK 포함 |
| `input.mouse_move` | hidio | `MouseMoveEvent` | absolute+percent 권장 |
| `input.mouse_click` | hidio | `MouseButtonEvent` | move + button down/up |
| `input.mouse_scroll` | hidio | `MouseWheelEvent` | 기존 |
| `apps.list` | projection | `ApplicationListRequest 0x80E1` | 기존 |
| `apps.launch` | projection | `ApplicationLaunchRequest 0x80E3` | 기존, allowedApps 정책 |
| `apps.terminate` | projection | `ApplicationTerminateRequest 0x80E5` | 기존 |
| `clipboard.read` | clipboard | `GetClipboardRequest 0x8006` | 기존 |
| `clipboard.write` | clipboard | (`SetClipboard*` — msgdef 확인 필요) | 부분 |
| `files.upload` | transfer | `TransferStartNotification 0x8001` | 기존 |
| `files.download` | transfer | (서버 → 클라이언트 방향) | 기존 |

### 도구 설계 원칙

1. **Action 도구는 대부분 `a11y.dispatch_action` 으로 통일.** 좌표 기반 클릭(`input.mouse_click`)
   은 fallback. AX 가 더 안정적이고 LLM 친화적이다 (좌표 안 흔들림).
2. **`screen.capture` 는 caching 가능**. 같은 프레임에 대해 여러 도구 호출이 일어날 수 있으므로
   게이트웨이 측에 짧은 TTL(500ms~1s) 캐시 권장.
3. **`a11y.get_tree` 는 maxDepth 강제**. LLM 컨텍스트를 폭파시키지 않도록 기본 depth 3,
   includeSnapshots 기본 false.
4. **읽기/쓰기 분리**. MCP 의 `read-only` 도구와 `mutation` 도구를 명확히 라벨링해 에이전트
   사이드의 confirmation prompt 를 쉽게 만든다.

---

## 7. 부족한 작업 항목 (Punch List)

### 7.1 프로토콜 (msgdef)

- [ ] `screen_capture.mdproto.md` 신규 — `CaptureScreenRequest 0x800A` / `Response 0x800B`
- [ ] `accessibility.mdproto.md` 보강 — `GetAccessibilityTreeRequest` 의 루트 trees 정책 명시
      (어떤 윈도우/앱이 루트로 잡히는지를 RFC-style 로 기술)
- [ ] (선택) `DispatchActionRequest` 결과의 `errorCode` 표준화 — 현재는 자유 텍스트

### 7.2 NoctilucaServer (Swift)

- [ ] `AppWindowRegistry.swift` 신설 — UUID ↔ AXUIElement (윈도우/뷰) 매핑
- [ ] `AccessibilityTreeBuilder` 입구 확장 — 루트 = 활성 윈도우 / 포커스된 앱
- [ ] `handleDispatchActionRequest` switch 확장 — 11개 액션 추가
- [ ] `OneShotScreenCapturer.swift` 신설 — `CGDisplayCreateImage` / `SCScreenshotManager`
- [ ] `ProjectionChannel+screencapture.swift` 신설 — 스냅샷 핸들러
- [ ] (선택) `includeSnapshots` 플래그 구현
- [ ] (선택) accessibility audit 로그

### 7.3 libsirius (C++)

- [ ] `feature/accessibility/AccessibilityChannel.hpp` 신설 — 메시지 송수신 wrapper
      (현재는 일반 Channel 위에서 직접 조립 가능하지만, 게이트웨이 코드 가독성을 위해 권장)
- [ ] msgdef 자동 생성 헤더에 신규 `CaptureScreenRequest/Response` 가 포함되도록 빌드 검증
- [ ] (선택) `feature/clipboard/ClipboardChannel.hpp` — Spec 4 에서 일부 구현됨, 검토 필요

### 7.4 MCP 게이트웨이 (신규 프로젝트)

- [ ] 디렉토리: `NoctilucaMCPGateway/` (모노레포 최상위) 또는 별도 레포
- [ ] 언어 선택: **C++20 + libsirius** (cross-platform 기본) 또는 **Swift + SiriusKit** (Mac only)
  - 권장: C++. MCP SDK 는 TypeScript / Python / Go 가 주류이므로 C++ 게이트웨이 + 얇은 stdio
    JSON-RPC 어댑터가 가장 자연스럽다.
- [ ] MCP transport: stdio (가장 단순), 추후 SSE/HTTP 추가
- [ ] 도구 카탈로그 (위 표) 구현
- [ ] 설정: `~/.config/noctiluca-mcp/config.toml` (호스트 주소, 인증 패스워드, allowed tools)
- [ ] 어드레스북: 여러 호스트 등록, MCP `resources` API로 호스트 목록 노출

---

## 8. 단계별 로드맵

### Phase 0 — 게이트웨이 스켈레톤 (1주)
- libsirius 위에 stdio MCP 서버 booting
- 단일 도구 `host.connect(address, password)` → MainChannel 인증 완료까지

### Phase 1 — Read-only PoC (1–2주)
- `apps.list` (기존 메시지로 즉시 가능)
- `screen.capture` (server-side `OneShotScreenCapturer` + 신규 메시지)
- `a11y.get_tree` (현재 메뉴바 한정으로도 PoC 가능)

→ 이 시점에 "에이전트가 화면을 보고 메뉴바를 읽고 앱 목록을 안다" 가 성립.

### Phase 2 — Action MVP (2–3주)
- `a11y.dispatch_action` 의 `click`/`focus`/`setValue` 구현
- `input.type_text`, `input.send_keys`, `input.mouse_*` (모두 기존 HIDIO)
- `clipboard.read/write`

→ 에이전트가 메뉴바 + HID 좌표 클릭 + 텍스트 입력으로 워크플로우 가능.

### Phase 3 — Tree 확장 (3–4주)
- `AppWindowRegistry` + accessibility tree 루트 확장
- 일반 윈도우 내부 컨트롤까지 dispatch 가능
- subscribe 이벤트 확장

→ 진정한 의미의 "AI agent 가 macOS 앱을 GUI로 조작" 가능.

### Phase 4 — 안정화 / 보안 / 품질 (지속)
- audit 로깅, scope policy, sandbox 정책 검토
- includeSnapshots, vision 통합
- 다중 호스트 어드레스북, 호스트 상태 관찰

---

## 9. 리스크 / 한계

### 9.1 기술적

| 리스크 | 설명 | 완화 |
|--------|------|------|
| AX tree 비용 | 시스템 와이드 트리는 macOS에서 100ms~수초 걸릴 수 있음 | 기본 depth 제한, 포커스 윈도우 우선, includeSnapshots 기본 off |
| AX 권한 | NoctilucaServer 는 이미 권한 보유. 일부 앱(보안 입력 필드)은 AX 차단 | UI Action 실패 시 HID 좌표 클릭으로 fallback 가이드 |
| 좌표 / 디스플레이 변경 | 디스플레이 핫플러그 시 좌표 무효화 | `displayman` 이벤트 구독 → MCP 측에 displayChanged notification |
| ucs4 입력의 IME 충돌 | 한글 IME 활성 상태에서 ucs4 직접 주입 시 컴포지션 깨질 수 있음 | 게이트웨이가 먼저 IME off (cmd+space 등) 또는 클립보드 paste 우선 |
| Latency | 원격 게이트웨이의 경우 LAN 5ms, WAN 30-100ms — agent step 마다 누적 | 도구 호출을 가능한 batch (e.g., `dispatch_actions(list)`) |

### 9.2 보안 / 정책

- **자격 유출 = 호스트 장악.** 게이트웨이 구성에 명시적 위험 경고 필요.
- **MCP 은 LLM 이 임의 도구를 호출 가능한 모델.** prompt injection 으로 악의적 파일 다운로드,
  설정 변경 등이 일어날 수 있다 → audit log + 사용자 confirm UX 권장.
- **macOS App Sandbox / Notarization** — MCP 게이트웨이가 macOS 앱이라면 App Store 외 배포는
  notarization 필수. CLI 배포는 비교적 자유.
- **TCC 권한** — 게이트웨이 자체는 NoctilucaServer 에 위임하므로 TCC 다이얼로그가 게이트웨이
  쪽에 뜰 일은 없음.

### 9.3 정책 / 정렬

- 본 프로젝트의 `CLAUDE.md` 에 "옛 harbord(root) 경험 + Apple 개발자 정책에서 학습된 결정"
  으로 **단일 프로세스 / 단일 유저 데스크톱 모델 고정** 이 못 박혀 있다. MCP 게이트웨이는 이
  제약을 위반하지 않는다 — 별도 프로세스이지만 사용자 권한으로 동작하고, NoctilucaServer 는
  여전히 단일 유저 모델.

---

## 10. 외부 생태계 비교 — OpenClaw / CUA / Computer Use API

2025–2026년에 "에이전트가 컴퓨터를 직접 조작" 영역은 빠르게 성숙했다. Sirius MCP 게이트웨이를
설계할 때 이들 프로젝트와의 정합성/차별성을 의식하면 의사결정이 쉬워진다.

### 10.1 카테고리

| 카테고리 | 대표 프로젝트 | 핵심 |
|---------|--------------|------|
| **A. 메시지 게이트웨이형 에이전트** | OpenClaw (전 Clawdbot/Moltbot) | Discord/Slack/iMessage 등 메시지 앱과 LLM 을 잇는 self-hosted 게이트웨이. SKILL.md 기반 AgentSkills 로 능력 확장. **본 리서치의 "MCP 게이트웨이" 발상과 가장 인접한 모델.** |
| **B. Computer Use Agent (CUA)** | Anthropic Computer Use API, trycua/cua, Bytebot, OpenCUA, Fazm, coasty-ai/open-computer-use | "screenshot + click/type" 같은 저수준 도구를 LLM 에 노출하고 데스크톱 풀 제어. macOS/Linux/Windows. |
| **C. 학술/벤치마크** | OpenCUA / AgentNet / OSWorld / AgentNetBench | CUA 모델 학습용 대규모 데이터셋과 평가 벤치마크. 직접 경쟁자라기보다 측정 잣대. |

### 10.2 CUA 의 3가지 아키텍처

업계 리서치에 따르면 CUA 의 아키텍처는 셋으로 정리된다:

1. **Screenshot + Vision** — 화면 비트맵을 멀티모달 LLM 에 넘김. Anthropic Computer Use 의
   기본형. 어떤 앱이든 작동(호환성 ◎), 비용·latency·정확도 ▽.
2. **Accessibility API** — OS 의 a11y tree 를 직접 읽음. **본 프로젝트(Sirius) 채택 모델.**
   <200ms 의 빠른 정확한 조작. 단, AX 미노출 surface (Chromium content, canvas-based 앱) 무력.
3. **Hybrid** — AX 우선 + 미커버 surface 는 vision fallback. **Fazm, trycua/cua 채택.** 가장
   실용적.

→ **본 프로젝트의 권장 진화 방향: 2 → 3 (Hybrid).** §3.4 의 신규 `CaptureScreenRequest` 와
§3.1 의 `includeSnapshots` 가 이 hybrid 진화의 빌딩블록이다.

### 10.3 주요 프로젝트와의 차이

#### vs. **Anthropic Claude Computer Use API**

- Anthropic 의 도구 스키마 (`computer_20251124`) 는 `screenshot`, `mouse_move`, `left_click`,
  `type`, `key`, `scroll`, `wait`, `cursor_position`, `zoom(region)` 등 저수준 액션 + 단축키
  표기법(`key="ctrl+s"`)을 정의한다.
- **Sirius MCP 게이트웨이는 이 스키마를 그대로 노출하면 Claude Computer Use 의 클라이언트 측
  구현체가 된다.** `tool_result` 루프를 받아 Sirius 메시지로 번역하는 thin adapter 만 있으면
  됨.
- **강점**: 일반적 Computer Use 구현은 **로컬 머신** 만 제어. Sirius 위에서는 **원격 macOS
  호스트** 를 제어 — "Linux 위 Claude Code 가 멀리 있는 Mac 을 자기 컴퓨터처럼 사용" 시나리오.
- **약점**: `screenshot` 호출에 QUIC 한 왕복 추가 (LAN 1–3ms / WAN 30–100ms). zoom 도구는
  client-side crop 으로 무료 구현 가능.
- macOS 자체에서는 Anthropic Computer Use 가 Claude Code v2.1.85+ 에서 **Screen Recording +
  Accessibility 권한** 을 요구함 — Sirius 호스트는 이미 두 권한 보유.

#### vs. **trycua/cua** (오픈소스 macOS sandbox)

- cua: macOS-on-macOS native sandbox (Apple Silicon 하이퍼바이저), MIT, Computer SDK +
  cua-driver. **AX 가 안 통하는 Chromium/canvas/게임 엔진까지 vision 으로 커버** 가 최대 강점.
  cua-driver 는 사용자의 커서/포커스/Space 를 훔치지 않고 background 로 작업.
- Sirius: 격리 sandbox 미제공 (실제 호스트 직접 제어). 격리는 약함. **대신 멀티호스트 +
  원격 + 인증/인풋 인젝션 인프라가 production-grade.**
- **결합 가능성**: Sirius 호스트로 cua 의 가상 Mac 을 띄우고 그 안에 NoctilucaServer 설치 →
  "cua sandbox 안의 Mac 을 Sirius 로 원격 제어" 도 가능. 보안 + 멀티호스트 결합.

#### vs. **Bytebot** (클라우드 sandboxed 데스크톱)

- Bytebot: 클라우드에서 sandboxed Linux 데스크톱을 즉석으로 띄우고 에이전트가 그 안에서 작업.
  브라우저/파일/터미널/IDE 통합 워크스테이션. "에이전트가 격리된 환경에서 알아서 작업" 시나리오.
- Sirius: 사용자의 실제 macOS 환경. **"내 컴퓨터를 원격에서 도와줘"** 시나리오에 우위. 반대로
  "에이전트 단독 작업" 시나리오는 Bytebot 우위.

#### vs. **Fazm** — 본 프로젝트와 가장 직접적인 비교 대상

- Fazm 도 "AX 트리 우선 + ScreenCaptureKit + voice 입력" 으로 macOS 전용 에이전트. Local
  Llama/Mistral via Ollama 도 지원.
- 차이:
  - **Sirius 는 원격 프로토콜 기반**. Fazm 은 로컬 Mac 에서 돌아감. 에이전트(LLM 추론)가 Mac
    자체에 있을 필요가 없다는 게 본 프로젝트의 핵심 강점.
  - **Sirius 는 인증/멀티세션/HID 인젝션 인프라가 production-grade**. Fazm 은 비교적 신규.
  - Fazm 은 voice UX, Ollama 통합 등 **agent UX layer** 가 있음. Sirius 는 transport/protocol
    layer 만 — MCP 게이트웨이가 채워야 할 빈칸이 명확.

#### vs. **OpenClaw** (메시지 게이트웨이)

- OpenClaw 는 "메시지 앱 ↔ 에이전트" 다리. 본질적으로 **chat surface for an agent that does
  shell/web/file**, 컴퓨터 GUI 조작은 핵심이 아님 (AgentSkills 로 추가 가능).
- Sirius MCP 게이트웨이는 "**MCP client (LLM) ↔ 원격 GUI**" 다리. **상보적**: OpenClaw 위에
  Sirius MCP 를 AgentSkill 로 등록하면, "Slack 에서 봇한테 '내 Mac 의 Xcode 프로젝트 빌드해줘'
  라고 시키면 Sirius 통해 원격 Mac 조작" 같은 조합이 가능하다.
- **본 프로젝트가 OpenClaw 와 경쟁할 이유는 없다.** 오히려 OpenClaw 의 100+ AgentSkills
  카탈로그에 합류하는 것이 노출/유저 측면에서 유리.

### 10.4 보안 측면 — 외부 생태계의 교훈

- Cisco AI Security 가 OpenClaw 의 third-party AgentSkill 에서 **prompt injection 으로 데이터
  유출** 을 확인. SAP 가 OpenClaw 차단 정책 추진. **에이전트 게이트웨이는 본질적으로
  confused-deputy 공격면.**
- Anthropic Computer Use 도 prompt injection 분류기 + "meaningful action 시 user
  confirmation" 을 명시적 대응책으로 제공. classifier 가 의심스러운 스크린샷 발견 시 모델이
  사용자 confirm 요청.
- macOS Sequoia 가 일부 accessibility API 를 깨뜨려 다수의 CUA 가 동작 불능 — Sirius 도 같은
  위험에 노출. macOS 메이저 업데이트마다 회귀 테스트 필요.
- **Sirius MCP 게이트웨이 권장 대응**:
  - `dispatch_action` / `apps.launch` / `files.write` / `clipboard.write` 등 mutation 도구는
    기본적으로 user confirm
  - audit log (모든 호출을 NoctilucaServer 측에서 기록)
  - allowed-actions scope policy (게이트웨이 자격증명에 capability 첨부)
  - prompt injection 검출 (스크린샷 OCR + 의심스러운 명령 패턴 휴리스틱)

### 10.5 호환성 / 표준화 전략

- **단기 (Phase 1–2)**: Sirius MCP 게이트웨이가 **Anthropic Computer Use 도구 스키마
  (`computer_20251124`) 호환** 옵션 제공. 동일 게이트웨이가 두 surface 노출:
  - (a) **MCP server** (stdio/SSE) — 임의 MCP 클라이언트(Claude Code/Codex/Cursor/Cline 등)
  - (b) **Anthropic Computer Use 도구 호환** (HTTP) — Anthropic SDK 의 `tool_result` 루프에
    직접 끼워질 수 있도록
- **중기**: OpenCUA 의 AgentNetBench / OSWorld-Verified 등 공개 벤치마크에서 Sirius 게이트웨이
  + Claude/GPT 조합의 성능 측정 — 학술 신뢰도 확보.
- **장기**: 본 프로젝트가 정의한 `accessibility.mdproto` + 신규 `screen_capture.mdproto` 가
  **원격 CUA 프로토콜의 reference** 로 자리잡을 가능성. (현재 원격 CUA 프로토콜 표준은 사실상
  부재 — VNC/RDP 는 GUI streaming 만 다루고, MCP 는 도구 스키마만 다룸. Sirius 가 그 사이의
  공백을 메운다.)

### 10.6 차별화 요약

| 축 | Sirius 의 위치 | 비고 |
|---|---|---|
| AX-first | Fazm, cua-hybrid 와 동일 철학 | a11y.mdproto 가 LLM 사용을 명시적으로 가정 |
| 원격 transport | **거의 유일** | VNC/RDP 외에는 production 원격 a11y 프로토콜 없음 |
| 멀티호스트 | **거의 유일** | 어드레스북 모델로 자연스러움 |
| Sandbox 격리 | 약함 | cua/Bytebot 결합으로 보완 가능 |
| 비전 (vision fallback) | 미구현 | §3.4 신규 메시지로 보완 예정 |
| Anthropic Computer Use 호환 | 어댑터로 가능 | Phase 1 에 포함 권장 |
| LLM 추론 통합 | 없음 (의도된 분리) | 게이트웨이 = transport layer; 추론은 외부 LLM |

---

## 11. 결론

- Sirius 프로토콜은 이미 MCP 시나리오에 필요한 80% 이상이 갖춰져 있다. **accessibility 채널은
  심지어 mdproto 문서에 LLM 에이전트 사용 사례를 명시하고 있다.**
- 추가 작업은 **(a) 메시지 1쌍(스크린샷) 신규 정의, (b) 서버 측 dispatch_action 확장 + a11y
  tree 루트 확장, (c) 게이트웨이 프로세스 구현** — 명확하고 분리 가능.
- libsirius 기반 cross-platform 게이트웨이가 자연스럽다. macOS 외에 Linux/Windows 머신에서도
  Mac 호스트를 제어 가능.
- **외부 생태계 측면**: AX-first 모델은 Fazm 과 동일, **차별점은 원격 transport + 멀티호스트 +
  production-grade 인프라**. Phase 1 에 Anthropic Computer Use 도구 스키마 호환 어댑터를
  포함하면 즉시 Claude Code / Anthropic SDK 사용자에게 노출 가능.
- 다음 단계: Phase 0–1 PoC (게이트웨이 부팅 + read-only 도구 + Anthropic 스키마 어댑터) 로
  빠르게 가치 검증.

---

## 부록 A — 관련 파일 인덱스

### 프로토콜 정의
- `SiriusKit/.../msgdef/SiriusProtocol/v1/channels/projection/accessibility.mdproto.md`
- `SiriusKit/.../msgdef/SiriusProtocol/v1/channels/projection/appman.mdproto.md`
- `SiriusKit/.../msgdef/SiriusProtocol/v1/channels/clipboard/clipboard.mdproto.md`
- `SiriusKit/.../msgdef/SiriusProtocol/v1/channels/transfer/transfer.mdproto.md`
- `SiriusKit/.../msgdef/general.mdproto.md` (handshake/auth)

### 서버 구현
- `NoctilucaServer/feature/projection/ProjectionChannel+accessibility.swift`
- `NoctilucaServer/feature/projection/ProjectionChannel+appman.swift`
- `NoctilucaServer/feature/hidio/HIDIOChannel.swift`
- `NoctilucaServer/feature/hidio/EventInjector*.swift`
- `NoctilucaServer/feature/clipboard/ClipboardChannel.swift`
- `NoctilucaServer/feature/transfer/TransferChannel.swift`
- `NoctilucaServer/projection/AppMenuRegistry.swift`
- `NoctilucaServer/projection/AccessibilityTreeBuilder.swift`
- `NoctilucaServer/projection/DesktopContextManager.swift`

### 클라이언트 구현 (참고)
- `NoctilucaClient/core/feature/hidio/HIDIOChannel.swift` (Swift)
- `NoctilucaClientQt/dependencies/libsirius/include/libsirius/feature/hidio/LinuxKeycode.hpp` (C++)
- `NoctilucaClientQt/dependencies/libsirius/src/feature/` (C++ 채널 구현체들)

### 인증 플러그인
- `NoctilucaServer/plugins/builtins/auth/plugins/SimplePasswordAuthPlugin.swift`
- `NoctilucaServer/plugins/builtins/auth/plugins/PAMAuthPlugin.*`
- `NoctilucaServer/plugins/builtins/auth/plugins/NullAuthPlugin.swift` (Debug only)

---

## 부록 B — 외부 참고자료

### Anthropic Computer Use
- Anthropic, "Computer use tool" — Claude API Docs (`computer_20251124`).
- Anthropic, "Let Claude use your computer from the CLI" — Claude Code Docs.
- Anthropic, "Introducing computer use, a new Claude 3.5 Sonnet, and Claude 3.5 Haiku" (2024-10).
- Simon Willison, "Initial explorations of Anthropic's new Computer Use capability" (2024-10).

### Open-source Computer Use Agents (CUA)
- **trycua/cua** — Open-source infrastructure for Computer-Use Agents. Sandboxes, SDKs, benchmarks. macOS/Linux/Windows. MIT.
- **Bytebot** — Cloud sandboxed desktop agent. Parallel agents, full computer environment.
- **OpenCUA (xlang-ai)** — AgentNet 데이터셋, AgentNetTool, AgentNetBench. OpenCUA-72B 가 OSWorld-Verified 45.0% (오픈소스 SOTA).
- **Fazm** — macOS accessibility-first agent + voice 입력 + Ollama 통합.
- **coasty-ai/open-computer-use** — OSWorld 82% 달성 production-ready CUA.
- **ranpox/awesome-computer-use** — 큐레이션 리스트.

### Agent gateways
- **OpenClaw** (전 Clawdbot/Moltbot) — Self-hosted gateway connecting messaging apps (Discord/Slack/iMessage/...) to LLM agents. SKILL.md 기반 AgentSkills. 247K stars (2026-03).
- **NVIDIA NemoClaw** — OpenClaw 위에 privacy/security 컨트롤 추가한 스택.

### 보안
- Cisco AI Security 의 third-party OpenClaw AgentSkill 분석 — prompt injection / data exfiltration 사례.
- Anthropic, computer use 의 prompt injection 분류기 + user confirmation 정책.

---

*이 문서는 리서치 결과이며, 구현 착수 전에 개별 Phase 별 별도 plan/리뷰를 거치는 것을 권장한다.*
