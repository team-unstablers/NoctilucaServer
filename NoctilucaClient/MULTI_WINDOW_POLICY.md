# Multi-Window & Display Policy

NoctilucaClient의 멀티 디스플레이 지원 및 플랫폼별 윈도우 관리 정책을 정의합니다.

## 1. Overview

Noctiluca는 호스트의 다중 디스플레이 환경을 지원합니다. 클라이언트 플랫폼의 특성에 따라 디스플레이를 표시하고 관리하는 전략이 다릅니다.

- **macOS**: **Multi-Window** 전략. 필요에 따라 각 디스플레이를 별도의 OS 윈도우로 분리(Detach)하여 동시에 볼 수 있습니다.
- **iOS / iPadOS**: **Single-Window** 전략. 한 번에 하나의 디스플레이만 메인 뷰에 표시하며, 인앱 스위처를 통해 전환합니다.

## 2. macOS Policy

### Window Types

| 타입 | 설명 | 역할 |
|---|---|---|
| **MainWindow** | 앱의 메인 진입점 | - 세션 연결/설정/인증 UI<br>- 기본적으로 **Primary Display**의 화면을 표시<br>- 세션의 생명주기를 관리 (Main이 닫히면 연결 종료) |
| **SubdisplayWindow** | 보조 디스플레이 뷰어 | - 특정 **Secondary Display**의 화면만을 단독으로 표시<br>- 사용자가 명시적으로 'Detach' 했을 때만 생성됨 |

### Lifecycle & Behavior

1. **초기 상태 (Default)**
   - 세션 연결 직후에는 `MainWindow` 하나만 존재합니다.
   - `MainWindow`는 호스트의 Primary Display를 보여줍니다.

2. **Detach (창 분리)**
   - 사용자는 디스플레이 스위처 UI에서 특정 디스플레이를 **'별도 창으로 열기 (Detach)'** 할 수 있습니다.
   - Detach 시 새로운 `SubdisplayWindow`가 생성되고, 해당 디스플레이에 대한 `ProjectionSession`이 시작됩니다.
   - **초기 배치**: macOS 시스템 기본 동작(Cascading 등)을 따르며, 별도의 위치 보정은 수행하지 않습니다.

3. **Closing (종료)**
   - **SubdisplayWindow 닫기**: 해당 윈도우가 표시하던 디스플레이의 프로젝션 스트림(`ProjectionSession`)만 종료됩니다. 메인 세션은 유지됩니다.
   - **MainWindow 닫기**: **전체 세션이 종료**됩니다. 연결된 모든 `SubdisplayWindow`도 함께 닫힙니다.

## 3. iOS / iPadOS Policy

### Structure
- **Single Window per Session**: 하나의 연결 세션은 하나의 `MainWindow` (Scene) 안에서 처리됩니다.
- iPadOS의 경우 OS 차원의 멀티태스킹(Split View, Stage Manager)을 통해 여러 개의 Noctiluca 인스턴스를 실행하여 **여러 호스트에 동시 접속**하는 것은 가능합니다. 하지만 **하나의 호스트에 대한 멀티 윈도우**는 지원하지 않습니다.

### Switching
- `MainWindow` 내의 **디스플레이 스위처(Switcher) UI**를 통해 현재 보고 있는 화면을 다른 디스플레이로 전환합니다.
- 스위처 UX는 별도의 Figma 디자인을 따릅니다.

## 4. Input Routing Policy (Cross-Platform)

멀티 디스플레이 환경에서 마우스 입력이 올바른 화면으로 전달되도록, 모든 포인터 이벤트는 **타겟 디스플레이 ID**를 명시해야 합니다.

### Implementation Rule
- `MainWindow` 및 `SubdisplayWindow`의 뷰 레이어는 자신이 렌더링하고 있는 소스의 `displayID`를 알고 있어야 합니다.
- `HIDIOController`로 마우스 이벤트를 보낼 때, `scope` 필드에 해당 ID를 설정합니다.

```swift
// Example
controller.moveMouseRelative(
    to: delta, 
    scope: .displayId(self.currentDisplayID) // 필수
)
```

## 5. Technical Implications

- **ProjectionChannel**: N개의 `ProjectionSession`을 동시에 관리할 수 있어야 합니다. (이미 구현됨)
- **ProjectionSession**: 특정 `displayID`에 바인딩되어야 하며, 윈도우 생성/파괴 시 세션의 `start`/`stop`이 연동되어야 합니다.
- **DisplayLayoutManager**: 서버로부터 수신한 디스플레이 목록(`DisplayInfo`)을 관리하고, UI(스위처)에 데이터를 제공합니다.
