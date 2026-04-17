# Noctiluca Server — 가상 디스플레이 기능 계획서 (초안)

> 작성일: 2026-04-17
> 상태: **Draft** — 의사 결정 과정 기록용. 본격 구현 전 팀 내부 재검토 필요.
> 기반 리서치: [`docs/macOS-virtual-display-research.md`](./macOS-virtual-display-research.md)

---

## 0. TL;DR — 이 문서에서 내려진 결정 (외부 메모리)

나중에 이 문서로 돌아왔을 때 "이거 내가 어느 선에서 결정했었지?" 가 바로 보이도록, 핵심 판단을 한 페이지에 먼저 기록해둔다.

| # | 결정 사항 | 내용 |
|---|-----------|------|
| D1 | **API 세대** | 3세대 `CGVirtualDisplay` Private API (macOS 14+). 1·2세대는 검토 대상 아님. |
| D2 | **프로세스 모델** | 메인 서버 프로세스에서 직접 호출하지 않고, **별도 XPC 헬퍼 (`VirtualDisplayHelper.xpc`)** 로 분리. TCC/WindowServer 문제 회피 + 권한 격리. |
| D3 | **물리 디스플레이 비활성화** | 지원함 (`SLSConfigureDisplayEnabled(..., false)`). 단, **RAII 스타일 핸들**로 서버 측이 확실히 복원 책임을 진다. |
| D4 | **가상 디스플레이 수명 주기** | **이중 바인딩**: (1) 핸들 명시적 파괴가 정상 경로, (2) 미처 정리 못 한 것은 세션 종료 시 fallback cleanup. |
| D5 | **Sirius 네임스페이스** | 신규 채널을 만들지 않고 **기존 `displayman` 네임스페이스(opcode `0x8041~`) 확장**. 가상 디스플레이 opcode는 `0x8048~` 부터 할당 제안. |
| D6 | **DisplayLayoutManager V2** | 기존 V1(read-only + change-subscribe)을 갈아엎지 않고 부가 API를 얹는 형태. 호출부에서 물리/가상 구분 없이 `CGDirectDisplayID`로 다룬다. |
| D7 | **AppStream 통합** | 별도 feature가 아니라, AppStream 쪽이 가상 디스플레이를 *소비하는* 형태로 결합. AppStream 윈도우 라이프타임 ↔ VD 라이프타임 1:1 바인딩. |
| D8 | **App Store 배포** | 이미 Private API(`Gesu`) 사용 중이므로 배포 경로에 **영향 없음**. Private API 사용 사실은 고지 문서에 그대로 반영. |

---

## 1. 개요

Noctiluca Server에 **가상 디스플레이(Virtual Display)** 기능을 추가해, 호스트 Mac의 물리 디스플레이 구성과 무관하게 클라이언트에게 원하는 해상도·개수의 화면을 제공할 수 있도록 한다.

구현 기반은 macOS 14(Sonoma)+의 `CGVirtualDisplay` Private API이며, TCC/WindowServer 호환성을 위해 별도 XPC 헬퍼 프로세스를 두는 구조를 택한다.

이 기능은 크게 두 가지 방향에서 가치가 있다.

1. **일반 원격 데스크톱** — 멀티헤드 클라이언트와 싱글헤드(또는 헤드리스) 호스트 사이의 레이아웃 불일치를 해소한다. 클라이언트가 "내 Mac처럼" 원격 Mac을 쓸 수 있게 된다.
2. **AppStream (Experimental)** — 호스트와 클라이언트의 디스플레이 사이즈가 어긋나 원격 앱 윈도우를 자유롭게 이동·리사이즈 못 하던 제약을 완화한다. 전용 가상 디스플레이에 앱을 spawn 하는 식으로.

---

## 2. 배경 (Motivation)

### 2.1 지금까지의 한계

Noctiluca Server v0.9.x는 호스트의 **물리 디스플레이 레이아웃을 그대로** 클라이언트에 투영한다. 이 접근은 단순하고 투명하다는 장점이 있지만, 현실의 원격 데스크톱 사용 양상에서는 다음과 같은 마찰이 자주 발생한다.

- **해상도 불일치**: 클라이언트가 iPad Pro 12.9" (2732×2048)인데 호스트가 27" 5K이면, 다운스케일로 인해 가독성/커서 정밀도가 크게 떨어진다. 반대로 아이폰 mini ↔ 6K Pro Display XDR 조합은 매크로 스케일로 UI가 터무니없이 작게 보인다.
- **헤드 수 불일치**: 클라이언트는 듀얼 모니터 + 노트북 화면의 트리플 헤드인데 호스트는 싱글 디스플레이 iMac인 경우, 클라이언트의 작업 공간이 손실된다.
- **헤드리스 Mac**: 모니터가 연결되지 않은 Mac mini/Studio 호스트에서는 ScreenCaptureKit이 "캡처할 화면"을 인식하지 못해 Projection 시작 자체가 불안정해질 수 있다.
- **AppStream 윈도우 리사이즈 제약**: 현재 AppStream은 호스트 상의 실제 윈도우를 그대로 스트리밍한다. 클라이언트에서 윈도우를 호스트 화면 밖으로 드래그할 수 없고, 호스트 화면보다 큰 사이즈로 리사이즈해도 실질적으로 잘려 보인다.

### 2.2 왜 지금인가

- `CGVirtualDisplay` 기반 3세대 접근이 macOS 14+에서 충분히 안정화되었고, DeskPad / Lumen / BetterDisplay 등 검증된 레퍼런스가 다수 존재한다.
- Noctiluca Server의 공식 최소 지원 OS도 macOS 13 Ventura지만, 얼리버드 구매자의 실질 사용 OS 분포는 14+ 가 압도적이다. (텔레메트리는 현재 OFF 이나, App Store 리뷰/지원 채널의 질문 분포로 추정)
- AppStream을 "장난감 수준"에서 "실용 기능"으로 올리려면, 호스트 해상도에 묶이지 않는 윈도우 스트리밍이 필요하다.

---

## 3. 목표 / 비목표

### 3.1 Goals

- G1. 클라이언트 요청에 따라 서버에서 **동적으로 가상 디스플레이를 생성/파괴** 할 수 있다.
- G2. 가상 디스플레이는 **기존 Projection 파이프라인**(ScreenCaptureKit → VideoToolbox/WebP/... → ProjectionDataChannel)을 그대로 탈 수 있다.
- G3. 물리 디스플레이 + 가상 디스플레이가 한 호스트에서 **혼재 가능**하며, 어느 것을 캡처 대상으로 삼을지는 클라이언트/서버 정책으로 결정한다.
- G4. **AppStream 전용 가상 디스플레이**를 요청할 수 있는 API 경로를 제공한다. AppStream 윈도우 라이프타임과 VD 라이프타임이 연동된다.
- G5. **안전한 복원 보장**: 물리 디스플레이 비활성화를 허용하되, 어떤 종료 경로에서도 원복되도록 한다.

### 3.2 Non-goals

- NG1. **App Store 배포 호환성 회복** — Noctiluca Server는 이미 Private API(Gesu)를 사용하므로, 이 기능은 새로운 제약을 추가하지 않는다.
- NG2. **HDR 가상 디스플레이** — 최초 버전은 SDR만. HDR은 물리 디스플레이 HDR 지원 과제와 함께 별도 계획으로 뺀다.
- NG3. **macOS 13 이하 지원** — CGVirtualDisplay 가용성 문제. 가상 디스플레이 기능 자체는 macOS 14+ 전용 기능으로 못 박는다. (서버 본체 최소 사양은 유지)
- NG4. **macOS 외 호스트 지원** — Windows/Linux에서 호스트가 도는 시나리오는 아예 없다.
- NG5. **Navigator(클라이언트) 쪽의 가상 디스플레이** — 이 계획서는 *서버가 자기 자신에게 VD를 추가해 클라이언트에 보여주는* 케이스에만 국한한다. 클라이언트가 자신의 물리 화면을 서버로 공유하는 류의 기능(역방향)은 스코프 밖.

---

## 4. 유스케이스 (Use Cases)

### UC-1. 멀티헤드 클라이언트 / 싱글헤드 호스트

**상황.** 사용자는 회사에서 트리플 모니터 Windows 워크스테이션(Noctiluca Navigator for Windows)을 쓰고 있고, 집의 M2 Mac mini(싱글 HDMI 모니터 연결)에 원격 접속한다.

**현재.** Mac mini의 단일 화면이 3대 모니터 중 하나에 스트리밍되고, 나머지 두 모니터는 낭비된다.

**가상 디스플레이 적용 후.**
- 클라이언트 접속 시 Navigator가 "내 레이아웃(모니터 3대, 해상도/위치 지정)"을 서버에 요청.
- 서버는 (사용자 정책에 따라) 기존 물리 디스플레이를 비활성화하거나 유지한 채로, 클라이언트 레이아웃과 1:1 대응하는 가상 디스플레이들을 생성.
- 각 가상 디스플레이는 별도 Projection 세션으로 스트리밍되어, Navigator에서 **로컬 Mac처럼** 3헤드 모두 사용 가능.

### UC-2. AppStream 윈도우 자유 배치

**상황.** 사용자는 iPad Pro에서 Noctiluca Navigator로 호스트 Mac의 Xcode만 AppStream으로 띄워 쓰고 싶다.

**현재.** 호스트 Mac의 실제 해상도(가령 1440×900 built-in)에 묶여, iPad Pro에서 Xcode 창을 크게 키우면 호스트 쪽에서 창이 잘려 렌더링이 불안정해진다.

**가상 디스플레이 적용 후.**
- AppStream 시작 시, Navigator가 "이 앱은 2732×2048에서 돌리고 싶어"를 요청.
- 서버가 `NOCVirtualDisplayPurpose.appStream` 으로 전용 VD를 생성하고, 대상 앱을 해당 디스플레이로 이주시킨 뒤, 그 디스플레이를 스트리밍.
- 앱 종료 / AppStream 종료 시 VD도 자동 파괴.

### UC-3. 헤드리스 Mac 원격 접속

**상황.** Mac mini 서버를 선반에 두고 모니터 없이 운영하는 사용자. 첫 부팅 후 모니터를 뽑으면 "virtual display"가 macOS 자체에서 임시로 만들어지지만, 해상도/색공간이 들쑥날쑥하다.

**가상 디스플레이 적용 후.**
- 서버 설정에 "Always-on 가상 디스플레이" 옵션(Phase 2+) 을 두어, 호스트 기동과 함께 표준 해상도의 VD가 한 장 상시 존재하도록 한다.
- 클라이언트 접속 여부와 무관하게 일관된 캡처 타깃이 존재함 → Projection 파이프라인 안정화.

> **주의.** UC-3의 "always-on" 모드는 수명 주기 정책 측면에서 UC-1/UC-2와 다르다 (세션 바인딩이 아니라 서버 프로세스 바인딩). 본 계획서 Phase 1에서는 **UC-1, UC-2만 지원**하고, UC-3은 Phase 2+에서 별도 기획으로 다룬다.

---

## 5. 아키텍처 개요

```
┌──────────────────────────────────────────────────────────────┐
│                   NoctilucaServer.app (main)                 │
│                                                              │
│  ┌──────────────────────────┐   ┌────────────────────────┐   │
│  │  ProjectionChannel       │◀─▶│  DisplayLayoutManager  │   │
│  │  (Sirius, displayman ext)│   │          V2            │   │
│  └──────────────────────────┘   └───────────┬────────────┘   │
│                                             │                │
│                                       NSXPCConnection        │
│                                             │                │
└─────────────────────────────────────────────┼────────────────┘
                                              │
                                              ▼
┌──────────────────────────────────────────────────────────────┐
│              VirtualDisplayHelper.xpc (child)                │
│                                                              │
│  - CGVirtualDisplayDescriptor 생성                            │
│  - CGVirtualDisplay initWithDescriptor:                      │
│  - applySettings:                                            │
│  - SLSConfigureDisplayEnabled (활성화)                        │
│  - CGDisplaySetDisplayMode (모드 전환)                         │
│  - 프로세스 종료 시 모든 VD 자동 소멸                            │
└──────────────────────────────────────────────────────────────┘
```

### 5.1 Virtual Display Helper (XPC 서비스)

**역할.**
- `CGVirtualDisplay` 오브젝트의 실제 소유/생성/파괴.
- `SLSConfigureDisplayEnabled` 호출로 물리·가상 디스플레이의 enable/disable.
- `CGDisplaySetDisplayMode` 를 통한 모드 전환.

**왜 분리하는가.** 리서치(§1, Lumen `vd_helper`)에서 확인된 바와 같이, 메인 프로세스에서 직접 `CGVirtualDisplay`를 만들면 TCC / WindowServer 등록 타이밍 문제로 디스플레이가 시스템에 정상 노출되지 않는 케이스가 있다. 또한 Private API 호출을 격리함으로써, 서버 본체가 크래시해도 호스트 OS 디스플레이 구성을 비교적 안전하게 복원할 여지를 준다.

**번들링.**
- `NoctilucaServer.app/Contents/XPCServices/VirtualDisplayHelper.xpc`
- Bundle ID 예: `app.noctiluca.server.VirtualDisplayHelper`

**통신 방식.**
- `NSXPCConnection` + `@objc` 프로토콜.
- 가능하다면 Swift Concurrency(`async`) 친화적 래퍼를 메인 프로세스 쪽에 둔다.

**권한.**
- 헬퍼 자체는 최소 권한으로만. 화면 캡처(TCC) / 입력 인젝션 / 네트워크 등은 **모두 메인 프로세스 책임**. 헬퍼는 `CoreGraphics` + `SkyLight Private API` 접근만.

### 5.2 DisplayLayoutManager V2

기존 `DisplayLayoutManager` (`NoctilucaServer/projection/DisplayLayoutManager.swift`) 는 다음 두 가지만 한다.
- 현재 디스플레이 레이아웃 읽기
- 변경 이벤트 구독

V2는 여기에 다음 책임을 얹는다.
- **가상 디스플레이 acquire / destroy** (XPC 헬퍼를 통해)
- **디스플레이 활성 상태 제어** (`setActive`) — 물리/가상 공통
- **메인 디스플레이 승격** (`promoteToMain`)
- **레이아웃 재배치** (`arrange`, CGConfigureDisplayOrigin 래핑)
- **스펙 호환성 질의** (`supportsSpec`) 및 **스펙 변경** (`alterSpec`)

V2는 V1을 *대체하지 않는다*. 같은 클래스를 진화시키되, 기존 read-only API는 그대로 남긴다. 마이그레이션 영향 최소화.

### 5.3 Sirius 프로토콜 — `displayman` 네임스페이스 확장

**이미 존재하는 것 (v0.9.x 기준).**

| Opcode | 이름 | 용도 |
|--------|------|------|
| `0x8041` | `displayListRequest` | 디스플레이 목록 조회 |
| `0x8042` | `displayListResponse` | — 응답 |
| `0x8043` | `subscribeDisplayChangesRequest` | 변경 이벤트 구독 시작 |
| `0x8044` | `subscribeDisplayChangesResponse` | — 응답 |
| `0x8045` | `unsubscribeDisplayChangesRequest` | 구독 해제 |
| `0x8046` | `unsubscribeDisplayChangesResponse` | — 응답 |
| `0x8047` | `displayChangedEvent` | 변경 이벤트 푸시 |

또한 `DisplayKind.virtual = 3`, `DisplayState.isActive` 등은 **이미 모델링되어 있다**. 즉 가상 디스플레이라는 개념 자체는 프로토콜 레벨에서 예약된 상태.

**이 계획에서 추가 제안.**

| Opcode (제안) | 이름 | 용도 |
|---|------|------|
| `0x8048` | `acquireVirtualDisplayRequest` | 가상 디스플레이 생성 요청 |
| `0x8049` | `acquireVirtualDisplayResponse` | — 응답 (핸들 반환) |
| `0x804A` | `destroyVirtualDisplayRequest` | 핸들 기반 파괴 |
| `0x804B` | `destroyVirtualDisplayResponse` | — 응답 |
| `0x804C` | `setDisplayActiveRequest` | 물리/가상 공통 활성화 제어 |
| `0x804D` | `setDisplayActiveResponse` | — 응답 |
| `0x804E` | `promoteDisplayToMainRequest` | 메인 디스플레이 승격 |
| `0x804F` | `promoteDisplayToMainResponse` | — 응답 |
| `0x8050` | `arrangeDisplayRequest` | 레이아웃 재배치 |
| `0x8051` | `arrangeDisplayResponse` | — 응답 |
| `0x8052` | `alterDisplaySpecRequest` | 스펙 변경 |
| `0x8053` | `alterDisplaySpecResponse` | — 응답 |

> Opcode 번호는 확정 아님. `displayman` 연속 구간 유지 + `cursor`/`projection_*` 영역과 충돌 없도록 최종 할당 시 재검토.

---

## 6. 데이터 모델 & API 스케치 (Swift)

> 아래 코드는 **의사 코드(pseudo-code)** 이며, 타입/모듈 경계가 최종 구현과 정확히 일치하지 않을 수 있다. "이 방향으로 간다" 정도의 골격으로 읽어주길.

### 6.1 식별자

```swift
// 예: "app.noctiluca.server.0F3B1E5A-….virtual-display.A12C-…"
public typealias NOCVirtualDisplayIdentifier = String
```

식별자는 **세션 UUID + VD UUID** 조합의 RDNS 스타일 문자열. 서버 로그/크래시 리포트에서 "어느 세션이 만든 VD인가?"가 즉각 읽혀야 한다.

### 6.2 기본 타입

```swift
public enum NOCVirtualDisplayPurpose: Sendable {
    case virtualDisplay           // UC-1 범용
    case appStream                // UC-2 AppStream 전용
    case other(String)            // 확장 여지 (외부 플러그인 등)
}

public struct NOCDisplaySpec: Sendable, Equatable {
    public let viewportResolution: CGSize   // 논리 포인트 단위
    public let scaleFactor: CGFloat         // 1.0 / 2.0 ...
    // 이후 확장: color profile, refresh rate, HDR, ...
}

public struct NOCVirtualDisplayHandle: Sendable {
    public let identifier: NOCVirtualDisplayIdentifier
    public let displayID: CGDirectDisplayID
    public let purpose: NOCVirtualDisplayPurpose
    public let metadata: [String: String]
}

public struct NOCScreen: Sendable {
    public let id: CGDirectDisplayID

    /// 뷰포트 프레임. origin = 좌측 상단, size = 포인트 단위.
    /// (주: macOS NSScreen 관례와는 Y 반전. 프로토콜 일관성을 위해 채택)
    public let frame: CGRect
    public let displayResolution: CGSize    // 실제 픽셀 해상도
    public let scaleFactor: CGFloat

    /// 가상 디스플레이인 경우에만 채워짐.
    public let virtualDisplayIdentifier: NOCVirtualDisplayIdentifier?

    /// 내부 전용. 외부 모듈에서 가급적 참조하지 말 것.
    nonisolated(unsafe) internal let backingNSScreen: NSScreen?
}
```

### 6.3 DisplayLayoutManager V2 API

```swift
public final class DisplayLayoutManager {

    // MARK: - V1 (기존, 변경 없음)
    public private(set) var displayLayouts: [CGDirectDisplayID: NOCScreen]
    public let displayChangeSubject: PassthroughSubject<DisplayChangeEvent, Never>
    // ... 기존 API 유지 ...

    // MARK: - V2 (신규)

    public private(set) var virtualDisplays:
        [NOCVirtualDisplayIdentifier: NOCVirtualDisplayHandle]

    /// 새 가상 디스플레이 생성.
    /// - 반환되는 핸들은 RAII 스타일로 취급. 명시적으로 destroyVirtualDisplay(_:)를
    ///   호출해서 정리하는 것이 정상 경로.
    public func acquireVirtualDisplay(
        relatedTo sessionID: UUID,
        purpose: NOCVirtualDisplayPurpose,
        spec: NOCDisplaySpec
    ) async throws -> NOCVirtualDisplayHandle

    public func destroyVirtualDisplay(
        _ handle: NOCVirtualDisplayHandle
    ) async throws

    /// 디스플레이 레이아웃 재배치.
    public func arrangeDisplay(
        _ displayID: CGDirectDisplayID,
        bounds: CGRect
    ) async throws

    /// 활성 상태 토글. 물리 디스플레이에도 적용 가능 (D3 결정 사항).
    public func setDisplayActive(
        _ displayID: CGDirectDisplayID,
        isActive: Bool
    ) async throws

    /// 메인 디스플레이 승격.
    public func promoteDisplayToMain(
        _ displayID: CGDirectDisplayID
    ) async throws

    /// 주어진 spec을 해당 디스플레이에 적용 가능한지.
    /// (FIXME: 이름 후보 — `supportsSpec`, `canApplySpec`, `isSpecSupported`)
    public func supportsSpec(
        displayID: CGDirectDisplayID,
        spec: NOCDisplaySpec
    ) -> Bool

    /// 디스플레이 spec 변경.
    public func alterDisplaySpec(
        displayID: CGDirectDisplayID,
        spec: NOCDisplaySpec
    ) async throws
}
```

### 6.4 사용 예 (Sirius 측)

```swift
// 시나리오: 클라이언트 레이아웃과 불호환 → 호스트 물리 디스플레이 전부 끄고 가상으로 덮어쓰기

let displays = try await projectionChannel.displayman.requestDisplayLayout()
for display in displays {
    try await projectionChannel.displayman.deactivateDisplay(display.id)
}

let vd1 = try await projectionChannel.displayman.requestVirtualDisplay(
    spec: DisplaySpec(resolution: CGSize(width: 1920, height: 1080),
                      position: .absolute(.zero))
)
try await projectionChannel.displayman.promoteDisplayToMain(vd1.id)

let vd2 = try await projectionChannel.displayman.requestVirtualDisplay(
    spec: DisplaySpec(resolution: CGSize(width: 1920, height: 1080),
                      position: .relative(.rightOf(vd1.id)))
)

try await projectionChannel.startProjection(.display(vd1.id))
try await projectionChannel.startProjection(.display(vd2.id))
```

---

## 7. 수명 주기 (Lifecycle)

### 7.1 이중 바인딩

가상 디스플레이는 다음 두 경로로 사라질 수 있다.

1. **정상 경로 — 핸들 명시적 파괴.** 클라이언트가 `destroyVirtualDisplay` 요청을 보내거나, 서버 측 소유자(예: AppStream 세션)가 해당 VD를 더 이상 필요로 하지 않을 때 명시적으로 `DisplayLayoutManager.destroyVirtualDisplay(_:)` 호출.
2. **Fallback 경로 — 세션 종료 시 cleanup.** Sirius 세션(혹은 Projection 채널)이 닫히거나 비정상 종료되면, `DisplayLayoutManager`는 해당 세션이 만든 VD 중 아직 살아 있는 것을 전부 파괴한다.

> **원칙.** 정상 경로가 실패해도 서비스가 망가지지 않도록, Fallback 경로를 **항상 준비**한다.

### 7.2 물리 디스플레이 복원 (RAII)

`setDisplayActive(_, false)` 로 물리 디스플레이를 끈 경우, 서버는 이를 "복원 의무가 있는 상태"로 추적해야 한다. 구체적으로:

- `DisplayLayoutManager` 내부에 `DeactivatedPhysicalDisplay` 장부 유지.
- 장부 엔트리 제거는 (a) 동일 세션에서 다시 `setDisplayActive(_, true)` 호출되거나 (b) 세션이 종료될 때만.
- 세션 종료 훅: `ProjectionChannel` teardown에 "내가 비활성화시킨 물리 디스플레이가 있으면 원상 복구" 단계를 강제.
- 서버 프로세스 비정상 종료 대비: helper XPC 프로세스 또한 자체 종료 시 (모든) 비활성화된 물리 디스플레이를 복원한다.

### 7.3 서버 재기동 / 크래시 시 Orphan 정리

XPC 헬퍼는 **부모 프로세스(NoctilucaServer main)가 죽으면 같이 죽는** 모델을 기본으로. 이 경우 자식에서 만든 `CGVirtualDisplay` 객체도 해제 → OS에서 해당 VD가 제거된다.

만약 어떤 이유로든 orphan VD가 남는다면 (예: helper가 좀비 상태), 서버 재기동 시 `CGGetOnlineDisplayList`로 전수 조사 후, Noctiluca 식별자 규약(`app.noctiluca.server.*`)에 해당하는 VD 중 "현재 세션과 무관한 것"을 강제 파괴.

---

## 8. 보안 및 정책

| 항목 | 정책 |
|------|------|
| **물리 디스플레이 비활성화 허용** | 서버 설정에서 사용자가 명시적으로 on/off. **기본값은 OFF** (Phase 1 기준). ON으로 둔 경우에도 클라이언트가 실제 비활성화를 요청하면 서버 UI에서 1회 확인(그냥 로그만 남길지, 모달을 띄울지는 §10 Open Question). |
| **최대 동시 VD 개수** | 세션당 4장을 기본 상한으로. 전체 호스트 기준으로는 16장 상한. 초과 시 `acquireVirtualDisplay`가 즉시 실패. (레퍼런스: BetterDisplay도 실용상 10장 이내 권장) |
| **최대 해상도** | VD당 7680×4320 (8K) 상한. 이 이상은 `supportsSpec = false` 반환. 물리 크기 선언은 27" 상당(597×336mm)로 고정하여 리서치 §1의 "물리 크기 검증" 문제 회피. |
| **TCC/권한 격리** | 헬퍼 XPC는 TCC 권한(화면 녹화/접근성)을 요청하지 않는다. 가상 디스플레이 생성/파괴만 담당. 화면 캡처는 어디까지나 메인 프로세스 책임. |
| **플러그인으로부터의 호출** | `NoctilucaServerExtensionV1` 등 플러그인은 이 API에 **직접 접근 불가**. 플러그인이 VD 필요로 하는 시나리오는 Phase 3+ 에서 ABI 설계 후 열어준다. |
| **known-hosts** | 기존 모델 그대로. 가상 디스플레이 관련 메시지가 추가됐다는 이유만으로 known-hosts 검증 로직은 변경되지 않는다. |

---

## 9. 단계적 도입 계획 (Phasing)

### Phase 0 — PoC (1~2주)
- [ ] 최소 형태의 `VirtualDisplayHelper.xpc` 번들 생성. `CGVirtualDisplay` 기반 1장 생성/파괴.
- [ ] 메인 프로세스에서 NSXPCConnection으로 헬퍼 호출, 생성된 VD가 `CGGetOnlineDisplayList`에 보이는지 검증.
- [ ] ScreenCaptureKit이 VD를 정상 캡처하는지 확인 (UC-1 핵심 전제).

### Phase 1 — 기본 기능 (3~4주)
- [ ] `DisplayLayoutManager` V2 API 구현 (acquire/destroy/arrange/setActive).
- [ ] Sirius `displayman` opcode 확장 (§5.3의 `0x8048~0x8051`).
- [ ] NoctilucaClient (macOS) 측 최소 UI — "내 레이아웃으로 동기화" 버튼.
- [ ] 세션 종료 시 orphan cleanup.
- [ ] **허용: 물리 디스플레이 유지, 가상 디스플레이 추가만.** (정책 D3의 비활성화는 Phase 2로)

### Phase 2 — 정책 & 레이아웃 완전체 (3~4주)
- [ ] `promoteDisplayToMain` / `alterDisplaySpec` / 물리 디스플레이 비활성화 허용.
- [ ] RAII 복원 보장 + 크래시 복원 경로.
- [ ] 서버 환경설정 UI: VD 관련 정책, 최대 개수, 기본 비활성화 허용 여부.

### Phase 3 — AppStream 통합 (2~3주)
- [ ] AppStream 시작 시 자동 VD 생성 (`NOCVirtualDisplayPurpose.appStream`).
- [ ] 대상 앱을 신규 VD로 이주 (윈도우 설정 API — 구체적인 방법은 §10 Open Question).
- [ ] 앱 종료 / AppStream 종료 시 VD 자동 파괴.

### Phase 4 (Optional / 후속) — Always-on 가상 디스플레이 (UC-3)
- [ ] 서버 기동 시 자동 VD 생성 옵션.
- [ ] 헤드리스 Mac에서 "기본 VD" 개념.

---

## 10. Open Questions (구현 전에 풀어야 할 것)

- **Q-10.1.** `NOCScreen.frame`의 origin 기준을 좌측 상단으로 할지 좌측 하단(Cocoa 관례)으로 할지. 프로토콜 일관성(클라이언트 Qt/Windows까지 고려) 관점에서는 좌측 상단이 자연스럽지만, 서버 내부 NSScreen 브리징 비용이 있다. 드래프트에서는 좌측 상단으로 잠정 결정.
- **Q-10.2.** AppStream에서 "앱을 특정 VD로 이주"하는 public/private API 경로. `NSWindow.setFrame` 수준으로 충분한가, 아니면 Private API(`_setWorkspace:` 계열)가 필요한가? 리서치 필요.
- **Q-10.3.** 물리 디스플레이 비활성화 시 호스트 측 UX. 모달 확인창? 조용히 비활성화? 전통 RDP의 "Lock screen on host" 스위치와 유사한 사용자 동의 플로우를 둘지.
- **Q-10.4.** ScreenCaptureKit이 VD를 캡처할 때 `SCDisplay` 속성(특히 `frame`/`displayID`)이 물리 디스플레이와 동일한 신뢰도로 채워지는지. Phase 0 PoC에서 반드시 검증.
- **Q-10.5.** Navigator Qt(Windows/Linux)에서 `displayman` 확장 opcode를 언제 지원할지. macOS Navigator 선행 → Qt는 Phase 1.5 즈음 합류가 자연스러움.
- **Q-10.6.** 헬퍼 XPC 서비스를 Gesu 스타일로 빌드 타임 코드생성에 녹일지, 아니면 별도 타깃으로 독립시킬지. 지금 감각으론 독립 타깃이 빌드·테스트 분리 면에서 유리.

---

## 11. 리스크

| 리스크 | 영향 | 완화 |
|-------|------|------|
| macOS 업데이트로 `CGVirtualDisplay` private symbol 변경 | 기능 완전 파괴 | Gesu 스타일의 동적 dlsym 래핑. 실패 시 "가상 디스플레이 미지원" 모드로 graceful degrade. |
| `SLSConfigureDisplayEnabled`로 물리 디스플레이 껐다가 복원 실패 | **호스트 Mac 블랙스크린** — 현장 사용자가 물리 접근 못하면 심각 | (a) 서버 프로세스 다운 시 helper 자동 복원, (b) helper 다운 시 메인이 대체 복원 시도, (c) "전통적" 복원 경로 실패 시 SSH 접근자를 위한 `noctilucactl restore-displays` CLI. |
| TCC 경로에서 헬퍼 프로세스만으로는 VD 생성 안 되는 엣지 케이스 | Phase 0에서 발견되면 아키텍처 재검토 | Phase 0을 길게 잡고, 실패 시 "메인 프로세스에서 직접 호출" 또는 "launchd daemon" 등 대안 검토. |
| Private API 사용 고지 누락 | 사용자 오해/신뢰 저하 | 릴리즈 노트와 `docs/earlybird-impl-status.md`에 명시. Gesu 케이스와 동일 수준으로 투명하게. |
| 과도한 개수의 VD로 WindowServer 포화 | 성능 저하/행업 | 정책상 상한(§8). 상한 도달 시 명확한 에러로 거절. |
| Qt Navigator 개발 지연으로 "macOS Navigator만 되는 비대칭 기능" 장기화 | UX 혼선 | 계획서 §9 Phasing에서 Qt 합류 시점을 명시. 마케팅/릴리즈 노트에서도 "현재 macOS Navigator 한정"을 정확히 기재. |

---

## 12. 참조

- 리서치 원문: [`docs/macOS-virtual-display-research.md`](./macOS-virtual-display-research.md)
- 현재 `DisplayLayoutManager` (V1): `NoctilucaServer/projection/DisplayLayoutManager.swift`
- 현재 `displayman` msgdef: `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/displayman+*.swift`
- AppStream 프로토콜: `SiriusProtocol/v1/channels/projection/appman.mdproto.md`
- KhaosT/CGVirtualDisplay — API 레퍼런스
- Stengo/DeskPad — 유저스페이스 VD 사용 예
- trollzem/Lumen — `vd_helper` 서브프로세스 패턴
