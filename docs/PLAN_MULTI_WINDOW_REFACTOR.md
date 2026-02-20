# NoctilucaClient Refactoring & Multi-Window Implementation Plan

본 문서는 `NoctilucaClient`의 구조적 리팩토링(`MainWindowViewModel` 제거)과 멀티 윈도우/디스플레이 정책(`MULTI_WINDOW_POLICY.md`) 적용을 위한 상세 설계 및 이행 계획을 기술합니다.

## 1. Core Architecture Refactoring

**목표**: 비대해진 `MainWindowViewModel`을 제거하고, `SessionWindowViewModel`과 `RemoteSession`을 세션 상태와 생명주기의 진실 공급원(Single Source of Truth)으로 격상시킵니다.

### 1.1 `RemoteSession`의 역할 정립 (Core Session Model)
`RemoteSession`은 연결 세션의 생명주기와 전역 상태를 관리하는 **핵심 모델**이 됩니다. UI 종속적인 상태는 배제하고, 여러 윈도우가 공유해야 할 데이터의 진실 공급원(Single Source of Truth) 역할에 집중합니다.

*   **Lifecycle Ownership**:
    *   연결(Startup), 인증(Auth), 종료(Shutdown) 및 리소스 정리를 총괄합니다.
    *   `NoctilucaClient` 인스턴스를 소유하며, 상위 레이어에 안정적인 인터페이스를 제공합니다.
*   **Shared State Management**:
    *   **세션 상태**: `phase`(연결 단계), `authChallenge`(인증 요청) 등.
    *   **데이터 채널**: `projection`(화면), `hidio`(입력) 채널 객체 관리.
    *   **공통 통계**: `pingRTT` 등 모든 윈도우가 공유하는 품질 지표.
*   **Exclusion**: UI 네비게이션, Alert 표시 여부, `AVSampleBufferDisplayLayer`와 같은 View 객체는 포함하지 않습니다.

### 1.2 `RemoteSessionManager`의 확장
기존 `NoctilucaClientManager`를 대체하여, 앱 수준에서의 연결 관리를 담당합니다.

*   **역할**:
    *   새로운 연결 요청(`User Action`)을 받아 `RemoteSession` 인스턴스를 생성(Factory)합니다.
    *   (iOS의 경우) 활성화된 세션 목록을 관리할 수도 있으나, 기본적으로는 **Session Factory** 역할에 집중합니다.

### 1.3 `SessionWindowViewModel` 도입 (Per-Window UI State)
각 윈도우(Main, Sub)는 자신만의 UI 상태를 관리하기 위해 `SessionWindowViewModel`을 가집니다.

*   **UI State**:
    *   해당 윈도우의 렌더링을 위한 `AVSampleBufferDisplayLayer` 관리.
    *   윈도우별 Alert 표시 여부(`shouldDisplayErrorAlert`) 및 로컬 경고(`inputWarning`).
    *   Sub Window의 경우, 타겟팅된 `targetDisplayID` 정보 보유.
*   **Binding**: `RemoteSession`을 관찰(@ObservedObject)하여 세션 상태 변화를 UI에 반영합니다.

---

## 2. Core Logic Extension (Multi-Display Support)

멀티 디스플레이 지원을 위해 하부 프로토콜 및 채널 로직을 확장합니다.

### 2.1 `ProjectionChannel` 확장
특정 디스플레이를 타겟팅하여 스트림을 요청할 수 있도록 기능을 확장합니다.

*   **Display Discovery**: `DisplayListResponse`를 캐싱하고 관리하는 `DisplayLayoutManager`를 고도화하여, 현재 사용 가능한 디스플레이 ID 목록을 제공합니다.
*   **Session Creation**:
    *   `createSession(for displayID: Int32) -> ProjectionSession` 메서드를 추가합니다.
    *   기존 `sessions` 딕셔너리를 `[DisplayID: ProjectionSession]` 형태로 관리하거나, `ProjectionSession` 내부에 `displayID` 속성을 추가하여 식별합니다.

### 2.2 Input Routing (`HIDIO`) 고도화
입력 이벤트가 어느 디스플레이에서 발생했는지 서버에 알립니다.

*   **Targeting**:
    *   `HIDIOController` 및 `PointerInputRouter`의 메서드(`moveMouse`, `click` 등)에 `targetDisplayID: Int32` 파라미터를 추가합니다.
    *   패킷 전송 시 `scope` 필드에 해당 ID를 설정합니다.

---

## 3. Platform-Specific Window Lifecycle Management

플랫폼별 UI 정책에 따라 윈도우 및 뷰의 생명주기를 관리하는 구현 전략입니다.

### 3.1 macOS: Multi-Window Strategy

macOS에서는 `AppKitMainWindowController`가 세션의 **Root Controller** 역할을 수행하며, 하위 윈도우들의 생명주기를 관리합니다.

#### **`AppKitMainWindowController` (The Root)**
*   **소유**: `RemoteSession` 인스턴스를 소유(`@StateObject` 또는 직접 보유)합니다.
*   **책임**:
    *   세션 연결/종료의 주체입니다. 이 윈도우가 닫히면 `RemoteSession.disconnect()`를 호출합니다.
    *   **`WindowManager` 역할 겸임**: 하위 윈도우 컨트롤러(`SubdisplayWindowController`)들의 레퍼런스를 배열로 관리합니다.
*   **Sub Window 관리**:
    *   사용자가 'Detach'를 요청하면 `SubdisplayWindowController`를 생성하고 `subWindowControllers` 배열에 추가합니다.
    *   Main 윈도우가 닫힐 때(`windowWillClose`), 배열에 있는 모든 Sub 윈도우를 닫고 메모리에서 해제합니다.

#### **`SubdisplayWindowController` (New Class)**
*   **역할**: 보조 모니터 화면을 단독으로 표시하는 윈도우입니다.
*   **구성**:
    *   `RemoteSession`을 공유받지만, **자신만의 `ProjectionSession`**을 가집니다. (예: `displayID=2`에 대한 세션)
    *   생성 시점에 `RemoteSession.projection.createSession(for: targetDisplayID)`를 호출하여 스트림을 시작합니다.
    *   윈도우가 닫히면(`windowWillClose`), 해당 `ProjectionSession`만 `stop()` 하고 `RemoteSession`은 유지합니다.
*   **입력 라우팅**:
    *   이 윈도우 내의 `MainPhaseContentView`는 입력 발생 시 자신의 `targetDisplayID`를 사용하여 `HIDIO` 이벤트를 전송합니다.

### 3.2 iOS: Single-Window Switcher

iOS는 단일 윈도우 내에서 뷰를 교체하는 방식을 사용합니다.

*   **`RemoteSession.Projection` State**:
    *   `currentDisplayID` 상태를 추가합니다.
    *   `ProjectionSession`은 한 번에 하나만 활성화하거나(리소스 절약), 백그라운드에서 유지할지 결정해야 합니다. (모바일 리소스를 고려해 **전환 시 재연결** 방식을 권장)
*   **Display Switcher UI**:
    *   툴바의 '모니터 아이콘'을 통해 사용 가능한 디스플레이 목록(`DisplayLayoutManager` 제공)을 보여줍니다.
    *   선택 시 `currentDisplayID`를 변경하고, `ProjectionChannel`에 세션 재생성을 요청합니다.

---

## 4. Implementation Steps

작업은 다음 순서대로 진행합니다.

### Step 1: Refactoring (State Separation)
1.  `RemoteSession`에 세션 생명주기 및 공통 상태 로직 강화.
2.  `SessionWindowViewModel`을 신설하여 `MainWindowViewModel`의 UI 전용 상태(Layer, Alert 등) 이관.
3.  `MainWindow` 및 `SubdisplayWindow`가 각각 `SessionWindowViewModel`을 생성하고 `RemoteSession`을 주입받도록 수정.
4.  `MainWindowViewModel.swift` 삭제.

### Step 2: Core Logic Extension
1.  `ProjectionChannel`: `createSession(for displayID: ...)` 구현.
2.  `HIDIO`: `targetDisplayID` 파라미터 추가 및 패킷 적용.

### Step 3: macOS Multi-Window UI
1.  `SubdisplayWindowController` 구현 (SwiftUI `HostingController` 기반).
2.  `AppKitMainWindowController`에 서브 윈도우 관리 로직 추가.
3.  UI(메뉴/컨텍스트 메뉴)에 'Detach' 액션 연결.

### Step 4: iOS UI & Finalize
1.  iOS용 Display Switcher 구현.
2.  통합 테스트 및 버그 수정.
