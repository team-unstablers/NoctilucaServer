# Noctiluca Server — 가상 디스플레이 기능 계획서 (초안)

> 작성일: 2026-04-17
> 상태: **Draft** — PoC 검증 1차 반영(2026-04-17). 본격 구현 전 팀 내부 재검토 필요.
> 기반 리서치: [`docs/macOS-virtual-display-research.md`](./macOS-virtual-display-research.md)

---

## 0. TL;DR — 이 문서에서 내려진 결정 (외부 메모리)

나중에 이 문서로 돌아왔을 때 "이거 내가 어느 선에서 결정했었지?" 가 바로 보이도록, 핵심 판단을 한 페이지에 먼저 기록해둔다.

| # | 결정 사항 | 내용 |
|---|-----------|------|
| D1 | **API 세대** | 3세대 `CGVirtualDisplay` Private API (macOS 14+). 1·2세대는 검토 대상 아님. |
| D2 | **프로세스 모델** | 메인 서버 프로세스에서 직접 호출하지 않고, **별도 헬퍼 바이너리 `nocvirtdisplay` 서브프로세스**로 분리. XPC 서비스는 쓰지 않음 — `CGVirtualDisplay`가 내부적으로 WindowServer와 XPC로 통신하므로, helper 프로세스 사망만으로도 OS-레벨 자동 cleanup이 보장된다(2026-04-17 PoC 확인). |
| D3 | **물리 디스플레이 비활성화** | 지원함 (`SLSConfigureDisplayEnabled(..., false)`). 단, **RAII 스타일 핸들**로 서버 측이 확실히 복원 책임을 진다. |
| D4 | **가상 디스플레이 수명 주기** | **이중 바인딩**: (1) 핸들 명시적 파괴가 정상 경로, (2) 미처 정리 못 한 것은 세션 종료 시 fallback cleanup. |
| D5 | **Sirius 네임스페이스** | 신규 채널을 만들지 않고 **기존 `displayman` 네임스페이스(opcode `0x8041~`) 확장**. 가상 디스플레이 opcode는 `0x8048~` 부터 할당 제안. |
| D6 | **DisplayLayoutManager V2** | 기존 V1(read-only + change-subscribe)을 갈아엎지 않고 부가 API를 얹는 형태. 호출부에서 물리/가상 구분 없이 `CGDirectDisplayID`로 다룬다. |
| D7 | **AppStream 통합** | 별도 feature가 아니라, AppStream 쪽이 가상 디스플레이를 *소비하는* 형태로 결합. AppStream 윈도우 라이프타임 ↔ VD 라이프타임 1:1 바인딩. |
| D8 | **App Store 배포** | 이미 Private API(`Gesu`) 사용 중이므로 배포 경로에 **영향 없음**. Private API 사용 사실은 고지 문서에 그대로 반영. |
| D9 | **Helper 바이너리 외부 사용 정책** | `nocvirtdisplay` 는 형식적으로 독립 실행 가능하나, **유효한 Noctiluca Server 라이선스 보유자의 개인 스크립팅 용도**에 한정(honor-system, 라이선스 런타임 검증 없음). CLI/출력 포맷은 **안정 ABI로 약속하지 않는다.** `--help` NOTE 블록에 같은 취지 명시. |

---

## 1. 개요

Noctiluca Server에 **가상 디스플레이(Virtual Display)** 기능을 추가해, 호스트 Mac의 물리 디스플레이 구성과 무관하게 클라이언트에게 원하는 해상도·개수의 화면을 제공할 수 있도록 한다.

구현 기반은 macOS 14(Sonoma)+의 `CGVirtualDisplay` Private API이며, 안정성·권한 격리·자동 cleanup을 위해 별도 헬퍼 바이너리(`nocvirtdisplay`) 서브프로세스 구조를 택한다.

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
│                            posix_spawn + pipe (stdout/stderr)│
│                            + lifetime pipe (EOF 감지)         │
│                                             │                │
└─────────────────────────────────────────────┼────────────────┘
                                              │
                                              ▼
┌──────────────────────────────────────────────────────────────┐
│        nocvirtdisplay  (helper binary, child process)        │
│                                                              │
│  - ArgumentParser-based CLI                                  │
│  - CGVirtualDisplayDescriptor 생성                           │
│  - CGVirtualDisplay initWithDescriptor:                      │
│  - applySettings:                                            │
│  - stdout: "<DisplayID>\n"                                   │
│  - stderr: "nocvirtdisplay: <reason>"                        │
│  - SIGINT / SIGTERM → 즉시 종료                              │
│  - 프로세스 사망 → WindowServer가 내부 XPC 끊김 감지           │
│    → 해당 프로세스가 만든 VD 전부 자동 제거 (OS-level)        │
└──────────────────────────────────────────────────────────────┘
```

### 5.1 Virtual Display Helper (`nocvirtdisplay` 서브프로세스)

**역할.**
- `CGVirtualDisplay` 오브젝트의 실제 소유/생성.
- (향후 서브커맨드로) `SLSConfigureDisplayEnabled` 호출로 물리·가상 디스플레이의 enable/disable.
- (향후 서브커맨드로) `CGDisplaySetDisplayMode` 를 통한 모드 전환.

**왜 XPC 서비스가 아닌 일반 서브프로세스인가.** 초기 드래프트에서는 `NSXPCConnection` 기반 XPC 서비스를 검토했다. 그러나 2026-04-17 PoC에서 다음이 확인됨:

- `CGVirtualDisplay` 자체가 내부적으로 WindowServer와 XPC로 통신한다.
- 즉 **"helper 프로세스 사망 → WindowServer가 XPC 끊김 감지 → 해당 프로세스가 만든 VD 자동 정리"** 라는 OS-레벨 cleanup 경로가 이미 내장되어 있다.
- 따라서 helper를 `.xpc` 서비스 번들로 만들 필요 없이, **일반 서브프로세스 바이너리**로도 "고아 VD 방지" 보장을 공짜로 얻을 수 있다.

서브프로세스 쪽이 가지는 추가 장점:
- 빌드/테스트가 단순 (하나의 실행 바이너리, ArgumentParser로 CLI 구성).
- 라이선스 보유 사용자의 개인 스크립팅 용도로 **제한 노출** 가능 (D9).
- 크래시 시 코어 덤프 수집·디버깅이 XPC 서비스 대비 용이.

XPC 대비 감수하는 것:
- `NSXPCConnection`의 `invalidationHandler` / `interruptionHandler` 같은 공짜 훅이 없다. 부모 측에서 `waitpid` / `kevent EVFILT_PROC` 등으로 수명 감지를 직접 구현해야 한다.
- 구조화된 RPC가 아닌 line-based stdout 프로토콜. 메시지가 복잡해지면 파서 부담이 생길 수 있음. (현재 설계 범위는 "DisplayID 한 줄 + 시그널로 종료" 이므로 충분히 단순.)

**번들링.**
- `NoctilucaServer.app/Contents/Helpers/nocvirtdisplay`
- 독립 Swift 타깃. Swift ArgumentParser 기반 CLI.

**부모 → 자식 호출 (개요).**

```swift
// 부모 측 (Swift, 개념 스케치)
let pid = try spawnChild(
    executablePath: noctilucaServerBundle.helpersURL
        .appendingPathComponent("nocvirtdisplay").path,
    argv0: "nocvirtdisplay",  // ps / Activity Monitor 표시용
    arguments: [
        "--identifier", handle.internalIdentifier,
        "--serial-num", handle.serialNum,
        "2560x1440@60+2x,1920x1080@60+2x"
    ]
)
// 자식의 stdout 한 줄에서 DisplayID 파싱 → NOCVirtualDisplayHandle 에 저장
```

**CLI 인터페이스 (2026-04-17 PoC 기준).**

```
USAGE: nocvirtdisplay [--identifier <id>] [--serial-num <sn>] <specs>

<specs>  =  "WxH@RATE[+<scale>x]{,...}"
             예: 640x480@59.94+1x,1280x720@60+2x,3840x2160@29.97
             (하나의 VD가 여러 모드를 동시에 노출할 수 있다.
              첫 모드가 기본값으로 활성화됨.)

OUTPUTS
  stdout   성공 시 DisplayID 10진수 한 줄
  stderr   에러 발생 시 "nocvirtdisplay: <reason>"

EXIT CODES
  0   정상 종료
  1   CGVirtualDisplay 초기화 실패 (descriptor rejected)
  2   applySettings 실패
  3   displayID 획득 실패 (0 반환)
  64  인자 파싱 실패 (ArgumentParser 기본)
```

**권한.**
- 헬퍼 자체는 TCC 권한(화면 녹화/접근성)을 요청하지 않는다.
- `posix_spawn`된 자식은 기본적으로 부모의 TCC 승인을 상속하지만, 헬퍼 구현은 그 권한을 **사용하지 않는다**. 화면 캡처 / 네트워크 / 입력 인젝션은 어디까지나 메인 프로세스 책임.

### 5.2 DisplayLayoutManager V2

기존 `DisplayLayoutManager` (`NoctilucaServer/projection/DisplayLayoutManager.swift`) 는 다음 두 가지만 한다.
- 현재 디스플레이 레이아웃 읽기
- 변경 이벤트 구독

V2는 여기에 다음 책임을 얹는다.
- **가상 디스플레이 acquire / destroy** (서브프로세스 helper 를 통해)
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

### 6.1 식별자 — 내부 ID와 외부 표시명 분리

```swift
// 예: "app.noctiluca.server.0F3B1E5A-….virtual-display.A12C-…"
public typealias NOCVirtualDisplayIdentifier = String
```

`NOCVirtualDisplayIdentifier` 는 **세션 UUID + VD UUID** 조합의 RDNS 스타일 문자열로, **내부 식별자**다. 서버 로그/크래시 리포트/crash dump 등에서 "어느 세션이 만든 VD인가?" 가 즉각 읽혀야 하는 곳에만 쓴다.

> **표시명은 별도로 분리한다.** macOS 시스템 설정의 "디스플레이" 화면, Activity Monitor 등 **사용자에게 노출되는 이름**은 `NOCDisplaySpec.displayName` 필드에 실어 전달한다 — 내부용 RDNS 문자열이 시스템 UI에 그대로 새면 흉측하기 때문. (2026-04-17 PoC 확인: `nocvirtdisplay --identifier 'testrun'` 결과 시스템 설정에 **`Noctiluca Virtual Display (testrun)`** 로 표시되며, 이 문자열이 곧 *외부 표시명* 역할을 함.)

### 6.2 기본 타입

```swift
public enum NOCVirtualDisplayPurpose: Sendable {
    case virtualDisplay           // UC-1 범용
    case appStream                // UC-2 AppStream 전용
    case other(String)            // 확장 여지 (외부 플러그인 등)
}

/// 가상 디스플레이가 노출할 개별 모드.
/// `nocvirtdisplay` CLI의 "WxH@RATE+<scale>x" 토큰 하나에 대응.
public struct NOCDisplayMode: Sendable, Equatable, Hashable {
    public let resolution: CGSize     // 픽셀 단위 (예: 2560×1440)
    public let refreshRate: Double    // Hz (예: 60.0, 59.94)
    public let scaleFactor: CGFloat   // @1x / @2x — Retina 여부
}

/// 가상 디스플레이 사양.
/// - 하나의 VD는 **여러 모드를 동시에 노출**할 수 있다.
///   (2026-04-17 PoC: 2560×1440@60+2x 하나만 넘겨도 시스템 설정의
///    해상도 목록에 1920×1080 / 1600×900 / 1280×720 가 자동 파생돼 나타난다.
///    복수 모드를 명시적으로 실어주면 그 조합이 그대로 노출됨.)
/// - `modes` 배열의 **첫 번째 원소**가 기본(Default)으로 활성화된다.
public struct NOCDisplaySpec: Sendable, Equatable {
    /// 사용자 노출용 표시명. 시스템 설정 "디스플레이" 에 그대로 뜸.
    public let displayName: String
    public let modes: [NOCDisplayMode]
    // 이후 확장: color profile, HDR, physical size override, ...
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
    /// - 내부적으로 `nocvirtdisplay` 서브프로세스를 `posix_spawn` 하고,
    ///   stdout 의 DisplayID 한 줄을 파싱해 핸들을 구성한다.
    /// - 반환되는 핸들은 RAII 스타일. destroyVirtualDisplay(_:)가 정상 경로.
    public func acquireVirtualDisplay(
        relatedTo sessionID: UUID,
        purpose: NOCVirtualDisplayPurpose,
        spec: NOCDisplaySpec
    ) async throws -> NOCVirtualDisplayHandle

    /// 핸들 기반 파괴. 해당 helper 프로세스에 SIGTERM → WindowServer가 VD 제거.
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

1. **정상 경로 — 핸들 명시적 파괴.** 클라이언트가 `destroyVirtualDisplay` 요청을 보내거나, 서버 측 소유자(예: AppStream 세션)가 해당 VD를 더 이상 필요로 하지 않을 때 명시적으로 `DisplayLayoutManager.destroyVirtualDisplay(_:)` 호출 → 해당 helper 프로세스에 SIGTERM.
2. **Fallback 경로 — 세션 종료 시 cleanup.** Sirius 세션(혹은 Projection 채널)이 닫히거나 비정상 종료되면, `DisplayLayoutManager`는 해당 세션이 만든 모든 helper 프로세스에 SIGTERM을 일괄 송신.

> **원칙.** 정상 경로가 실패해도 서비스가 망가지지 않도록, Fallback 경로를 **항상 준비**한다.

### 7.2 물리 디스플레이 복원 (RAII)

`setDisplayActive(_, false)` 로 물리 디스플레이를 끈 경우, 서버는 이를 "복원 의무가 있는 상태"로 추적해야 한다. 구체적으로:

- `DisplayLayoutManager` 내부에 `DeactivatedPhysicalDisplay` 장부 유지.
- 장부 엔트리 제거는 (a) 동일 세션에서 다시 `setDisplayActive(_, true)` 호출되거나 (b) 세션이 종료될 때만.
- 세션 종료 훅: `ProjectionChannel` teardown에 "내가 비활성화시킨 물리 디스플레이가 있으면 원상 복구" 단계를 강제.
- 서버 프로세스 비정상 종료 대비: helper 프로세스 측도 자체 종료 시(부모 파이프 EOF 감지 포함) 비활성화된 물리 디스플레이를 복원하고 마무리.

### 7.3 헬퍼 / 서버 종료 시 자동 정리

`CGVirtualDisplay` 는 내부적으로 WindowServer 와 XPC 채널을 유지하며, 이 채널은 **프로세스 단위**다. 해당 프로세스가 어떤 경로로든 종료되면 WindowServer 가 XPC 끊김을 감지하고, **그 프로세스가 만든 VD 전부를 자동 제거**한다.

이 OS-레벨 cleanup 경로 덕분에 Noctiluca 쪽에서 수동으로 관리할 범위는 상당히 좁다.

| 사건 | 결과 |
|------|------|
| `nocvirtdisplay` 프로세스 정상 종료 (SIGTERM) | 해당 프로세스가 만든 VD 전부 자동 소멸 |
| `nocvirtdisplay` 프로세스 크래시 | 동일 (WindowServer 측 XPC 끊김 감지) |
| 부모(NoctilucaServer main) 정상 종료 | 부모는 종료 직전 모든 활성 helper 에 SIGTERM 송신 |
| 부모(NoctilucaServer main) 크래시 | 자식 helper 는 launchd 로 reparent 되어 생존 가능 → §7.3.1 |

#### 7.3.1 부모 사망 시 helper 생존 방지

macOS 는 Linux 의 `prctl(PR_SET_PDEATHSIG)` 같은 자동 사망 훅을 제공하지 않는다. 따라서 helper 쪽에서 부모 생존을 감시해야 한다. 설계 옵션:

- **라이프타임 파이프 + EOF 감지** *(권장)* — 부모가 `posix_spawn` 시 unnamed pipe 한 쌍을 열어 읽기 FD를 자식에게 넘긴다. 부모 사망 시 파이프가 닫히고 자식은 `read()` 에서 EOF → self-terminate.
- `kqueue` + `EVFILT_PROC` + `NOTE_EXIT` 로 부모 pid 감시. 더 직접적이지만 race 와 `getppid()` 폴링 조합이 필요.

구현 단순성과 신뢰도 면에서 **파이프 EOF 방식**을 채택한다.

#### 7.3.2 재기동 시 잔존 VD 탐지 (세이프티 넷)

그래도 어떤 이유로든 orphan VD가 남는다면, 서버 재기동 시 `CGGetOnlineDisplayList` 로 전수 조사 후, Noctiluca 식별자 규약(`app.noctiluca.server.*`) 매칭 + 현재 세션과 무관한 VD → 강제 파괴.

---

## 8. 보안 및 정책

| 항목 | 정책 |
|------|------|
| **물리 디스플레이 비활성화 허용** | 서버 설정에서 사용자가 명시적으로 on/off. **기본값은 OFF** (Phase 1 기준). ON으로 둔 경우에도 클라이언트가 실제 비활성화를 요청하면 서버 UI에서 1회 확인(그냥 로그만 남길지, 모달을 띄울지는 §10 Open Question). |
| **최대 동시 VD 개수** | 세션당 4장을 기본 상한으로. 전체 호스트 기준으로는 16장 상한. 초과 시 `acquireVirtualDisplay`가 즉시 실패. (레퍼런스: BetterDisplay도 실용상 10장 이내 권장) |
| **최대 해상도** | VD당 7680×4320 (8K) 상한. 이 이상은 `supportsSpec = false` 반환. 물리 크기 선언은 27" 상당(597×336mm)로 고정하여 리서치 §1의 "물리 크기 검증" 문제 회피. |
| **TCC/권한 격리** | helper 는 TCC 권한(화면 녹화/접근성)을 요청하지 않는다. 가상 디스플레이 생성/파괴만 담당. 화면 캡처는 어디까지나 메인 프로세스 책임. (`posix_spawn` 된 자식은 부모의 TCC 승인을 상속하지만, helper 구현은 그 권한을 *사용하지 않음*) |
| **플러그인으로부터의 호출** | `NoctilucaServerExtensionV1` 등 플러그인은 이 API에 **직접 접근 불가**. 플러그인이 VD 필요로 하는 시나리오는 Phase 3+ 에서 ABI 설계 후 열어준다. |
| **Helper 바이너리의 외부 직접 실행** | 라이선스 보유자의 개인 스크립팅 용도로만 한정 (D9, honor-system). CLI/출력 포맷은 안정 ABI 아님. `--help` NOTE에 명시. |
| **known-hosts** | 기존 모델 그대로. 가상 디스플레이 관련 메시지가 추가됐다는 이유만으로 known-hosts 검증 로직은 변경되지 않는다. |

---

## 9. 단계적 도입 계획 (Phasing)

### Phase 0 — PoC ← **대부분 완료 (2026-04-17)**
- [x] 최소 형태의 `nocvirtdisplay` 헬퍼 바이너리 구현. Swift ArgumentParser CLI 기반, `CGVirtualDisplay` 1장 생성/파괴.
- [x] 생성된 VD 가 `CGGetOnlineDisplayList` 에 노출되고 **시스템 설정 → 디스플레이**에 표시됨 (`Noctiluca Virtual Display (testrun)`; 2560×1440 기본 + 1920×1080 / 1600×900 / 1280×720 모드).
- [ ] ScreenCaptureKit 이 VD 를 정상 캡처하는지 확인 (UC-1 핵심 전제, 남은 유일한 Phase 0 작업).
- [ ] 부모↔자식 라이프타임 파이프(EOF 감지) PoC.

### Phase 1 — 기본 기능 (3~4주)
- [ ] `DisplayLayoutManager` V2 API 구현 (acquire/destroy/arrange/setActive).
- [ ] Sirius `displayman` opcode 확장 (§5.3의 `0x8048~0x8051`).
- [ ] NoctilucaClient (macOS) 측 최소 UI — "내 레이아웃으로 동기화" 버튼.
- [ ] 세션 종료 시 orphan cleanup (§7.3.2 세이프티 넷 포함).
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
- **Q-10.2.** AppStream에서 "앱을 특정 VD로 이주"하는 public/private API 경로. `NSWindow.setFrame` 수준으로 충분한가, 아니면 Private API(`_setWorkspace:` 계열)가 필요한가? Phase 3 착수 전 스파이크 필요.
- **Q-10.3.** 물리 디스플레이 비활성화 시 호스트 측 UX. 모달 확인창? 조용히 비활성화? 전통 RDP의 "Lock screen on host" 스위치와 유사한 사용자 동의 플로우를 둘지.
- **Q-10.4.** ScreenCaptureKit이 VD를 캡처할 때 `SCDisplay` 속성(특히 `frame`/`displayID`)이 물리 디스플레이와 동일한 신뢰도로 채워지는지. **Phase 0 잔여 작업**에서 반드시 검증.
- **Q-10.5.** Navigator Qt(Windows/Linux)에서 `displayman` 확장 opcode를 언제 지원할지. macOS Navigator 선행 → Qt는 Phase 1.5 즈음 합류가 자연스러움.
- **Q-10.6.** `arrangeDisplay` API 의 시그니처를 **단일 디스플레이 단위**로 둘지, **여러 디스플레이의 배치를 한 트랜잭션에 묶은 `applyDisplayArrangement([displayID: CGRect])`** 로 둘지. CGConfigureDisplayOrigin 은 "스냅" 동작을 하므로 후자 쪽이 의도대로 배치될 확률이 높다. (참고: 2019년 Stack Overflow 포스트 "macOS CGConfigureDisplayOrigin doesn't work as expected" Ken Thomases 답변.)
- ~~**Q-10.x. (舊)** 헬퍼 XPC 서비스를 Gesu 스타일로 빌드 타임 코드생성에 녹일지, 아니면 별도 타깃으로 독립시킬지.~~ **→ 해결 (D2 개정)**: 별도 타깃의 **서브프로세스 바이너리 `nocvirtdisplay`** 로 확정. 2026-04-17 PoC 로 아키텍처 검증 완료.

---

## 11. 리스크

| 리스크 | 영향 | 완화 |
|-------|------|------|
| macOS 업데이트로 `CGVirtualDisplay` private symbol 변경 | 기능 완전 파괴 | Gesu 스타일의 동적 dlsym 래핑. 실패 시 "가상 디스플레이 미지원" 모드로 graceful degrade. |
| `SLSConfigureDisplayEnabled`로 물리 디스플레이 껐다가 복원 실패 | **호스트 Mac 블랙스크린** — 현장 사용자가 물리 접근 못하면 심각 | (a) 서버 프로세스 다운 시 helper가 자체 복원, (b) helper 다운 시 메인이 대체 복원 시도, (c) "전통적" 복원 경로 실패 시 SSH 접근자를 위한 `noctilucactl restore-displays` CLI. |
| 부모(NoctilucaServer main) 사망 시 helper 생존 (orphan 프로세스 + orphan VD) | helper가 좀비로 남고 VD 도 잔존 | §7.3.1 라이프타임 파이프 EOF 감지로 1차 해소. §7.3.2 재기동 세이프티 넷으로 2차 방어. |
| Private API 사용 고지 누락 | 사용자 오해/신뢰 저하 | 릴리즈 노트와 `docs/earlybird-impl-status.md`에 명시. Gesu 케이스와 동일 수준으로 투명하게. |
| 과도한 개수의 VD로 WindowServer 포화 | 성능 저하/행업 | 정책상 상한(§8). 상한 도달 시 명확한 에러로 거절. |
| Qt Navigator 개발 지연으로 "macOS Navigator만 되는 비대칭 기능" 장기화 | UX 혼선 | 계획서 §9 Phasing에서 Qt 합류 시점을 명시. 마케팅/릴리즈 노트에서도 "현재 macOS Navigator 한정"을 정확히 기재. |
| Helper 바이너리 CLI/출력 포맷을 외부 사용자가 스크립트에서 고정 ABI로 취급 | 내부 인터페이스 변경 시 사용자 스크립트 깨짐 | `--help` NOTE에 "intended purpose 외 동작 보장 안 됨" 명시 (D9). 필요 시 major 버전 변경 시점에만 출력 포맷 변경. |

> **제거된 리스크.** "TCC 경로에서 헬퍼 프로세스만으로는 VD 생성이 안 되는 엣지 케이스" 는 2026-04-17 PoC 에서 일반 서브프로세스로부터 VD 생성이 정상 작동함을 확인하여 **해소**되었다.

---

## 12. 참조

- 리서치 원문: [`docs/macOS-virtual-display-research.md`](./macOS-virtual-display-research.md)
- 현재 `DisplayLayoutManager` (V1): `NoctilucaServer/projection/DisplayLayoutManager.swift`
- 현재 `displayman` msgdef: `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/displayman+*.swift`
- AppStream 프로토콜: `SiriusProtocol/v1/channels/projection/appman.mdproto.md`
- KhaosT/CGVirtualDisplay — API 레퍼런스
- Stengo/DeskPad — 유저스페이스 VD 사용 예
- trollzem/Lumen — `vd_helper` 서브프로세스 패턴
- Stack Overflow, "macOS CGConfigureDisplayOrigin doesn't work as expected" (Ken Thomases 답변, 2019) — §10 Q-10.6 근거
