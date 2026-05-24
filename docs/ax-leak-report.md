# DesktopContextManager 리소스 리크 조사 보고서

조사 대상: `NoctilucaServer/projection/DesktopContextManager.swift`
관련 파일: `AppMenuRegistry.swift`, `AccessibilityTreeBuilder.swift`,
`osapi/private/SkyLightPrivate.swift`, `feature/projection/ProjectionChannel+*.swift`

본 보고서는 코드 정독 기반의 정적 분석 결과를 정리한 것이며, 일부 항목은 Instruments
(Leaks / Allocations) 로 확정 검증이 필요하다. 검증이 필요한 항목은 *"확인 필요"* 로
태깅했다.

---

## TL;DR — 영향도 순 요약

| # | 항목 | 영향도 | 상태 |
| -- | ---- | ----- | ---- |
| 1 | winman `SubscribeWindowEvents` 가 채널 destroy 에서 정리되지 않고, 자동 생성된 `AppSession` 도 refcount 없이 유지 | 중간~높음 (AXObserver + refresh 지속) | 확정 |
| 2 | `AppMenuRegistry` 가 메뉴/컨텍스트 메뉴 AXUIElement 매핑을 pid prune 전까지 강하게 보존 | 중간 (세션 내 단조 증가 가능) | 확정 |
| 3 | `DesktopContextManager.shared.shutdown()` 가 호출되지 않아 NSWorkspace observer/세션이 서버 stop 후에도 유지 | 낮음~중간 (서버 재시작 경로) | 확정 |
| 4 | 종료된 PID 의 윈도우/앱 이벤트 구독이 prune 되지 않음 | 낮음 (디스패치 overhead), #1 과 결합 시 중간 | 확정, 설계상 의도 명시됨 |
| 5 | SkyLight 사설 API (`SLSWindowQuery*`, `SLSCopy*`) 의 +1 반환에 대한 ARC 관리 | **확인 필요 (잠재 고빈도 리크)** | 미확정 |
| 6 | `AppSession.stop()` 누락 시 `Unmanaged.passRetained` 가 영구 retain | 낮음 (assertion 으로 검출) | 방어 코드로 검출됨 |
| 7 | `fetchWindowList` / `globalWindowList` 의 `[CGWindowID: AXUIElement]` 맵을 매 refresh 마다 재구축 | 미미 (수명 짧음), 성능 비용 큼 | 확정, 설계상 의도 |

---

## 1. winman window subscription 과 `AppSession` 수명 불일치

### 현상
`ProjectionChannel+winman.swift` 의 `handleSubscribeWindowEventsRequest` 는
`DesktopContextManager.subscribeWindowEvents(...)` 가 반환한 subscription UUID 를
클라이언트에만 돌려주고, `ProjectionChannelState` 에 보관하지 않는다. 따라서 클라이언트가
명시적으로 `UnsubscribeWindowEventsRequest` 를 보내지 않고 채널이 닫히면
`ProjectionChannel.destroy()` 에서 이 구독을 회수할 방법이 없다.

또한 `DesktopContextManager.subscribeWindowEvents` 는 `ensureSessionsForSubscription` 을
통해 구독 대상 앱의 `AppSession` 을 자동 생성한다:

- filter 가 `.pid(...)` 로 추출 가능하면 해당 PID 들에 대해 `ensureSession(forPID:)`.
- filter 가 없거나 복합 필터라 PID 를 특정할 수 없으면 `runningApplications()` 전체에 대해
  `startMonitoring(app:)`.

반면 `unsubscribeWindowEvents(id:)` 는 `subscriptions.removeValue(forKey:)` 만 수행한다.
이 구독 때문에 생성된 `AppSession` 들은 owner/refcount 없이 `activeSessions` 에 남고,
앱 종료 또는 `DesktopContextManager.shutdown()` 전까지 `stop()` 되지 않는다.

### 정리 경로
- AppStream 경로는 `ProjectionChannelState.AppStreamSessionInfo.windowSubscriptionId` 를
  저장하고 `cleanupAppStreamSession` 에서 unsubscribe 하므로 stale subscription entry 는
  정리된다.
- singleWindow projection 의 resize subscription 은 `ProjectionSession.stop()` 에서
  unsubscribe 된다.
- 일반 winman `SubscribeWindowEventsRequest` 로 만든 구독은 channel state 에 없어서
  disconnect/destroy 시 자동 정리되지 않는다.
- unsubscribe 가 정상 호출되어도, 그 구독 때문에 만들어진 `AppSession` 은 정리되지 않는다.

### 영향
- stale `WindowEventSubscription` 자체는 작지만, callback closure 와 filter 를 계속 보존한다.
  closure 는 `[weak self]` 라서 `ProjectionChannel` 을 강하게 잡지는 않지만 dead callback 이
  dispatch loop 에 남는다.
- 더 큰 문제는 `activeSessions` 에 남는 `AppSession` 이다. 각 세션은 AXObserver runloop
  source, Combine pipeline, `monitoredWindows` 캐시, `Unmanaged.passRetained(self)` refCon 을
  보유한다.
- 구독자가 없어도 AX notification 이 들어오면 `refreshWindows()` 가 계속 실행된다.
  이 경로는 `fetchWindowList()` 와 `getSkyLightWindowInfo(for:)` 를 호출하므로, 항목 #5 의
  SkyLight ownership 문제가 실제 leak 이라면 누수 속도를 크게 증폭한다.
- filter 가 없는 window subscription 을 한 번 열었다 닫는 것만으로 현재 실행 중인 대부분의
  GUI 앱에 `AppSession` 이 생길 수 있다. 사용자가 앱을 종료하기 전까지 회수되지 않는다.

### 권장 조치
- `ProjectionChannelState` 에 일반 window subscription UUID 목록을 저장하고
  `ProjectionChannel.destroy()` 에서 전부 unsubscribe 한다. AppStream/accessibility 구독처럼
  channel-owned resource 로 취급해야 한다.
- `DesktopContextManager` 는 `AppSession` 생성 이유를 추적해야 한다. 최소 구현은
  `subscriptionID -> Set<pid_t>` 와 `pid -> owner count` 를 두고, unsubscribe 시 owner count 가
  0 이며 명시적으로 고정된 세션이 아니면 `stopMonitoring(pid:)` 를 호출하는 방식이다.
- one-shot window manipulation/focus 로 만든 세션도 같은 정책에 편입하거나, 명시적
  `session pin` 과 `idle reap` 을 분리한다. 현재 구조에서는 어떤 API 가 만든 세션인지
  구분되지 않는다.
- 서버 stop/restart 경로에서 `DesktopContextManager.shared.shutdown()` 을 호출하는 것은
  이 문제의 마지막 안전망이다(항목 #3).

---

## 2. `AppMenuRegistry` — 메뉴/컨텍스트 메뉴 AXUIElement 매핑 누적

### 현상
`AppMenuRegistry.shared` (싱글턴) 는 `register(element:pid:)` 호출마다 UUID 와
AXUIElement 의 양방향 매핑을 누적한다 (`idToEntry`, `elementIndex[pid]`).
`AccessibilityTreeBuilder.buildNode` 는 메뉴바 스냅샷과 popup/context menu 스냅샷의
*모든 노드* 마다 이 등록을 수행한다 (`AccessibilityTreeBuilder.swift:86`).

중요한 정정: 현재 `GetAccessibilityTreeRequest` 의 루트 요청과
`SubscribeAccessibilityTreeUpdatesRequest` 는 활성 AppStream 세션을 요구한다. 따라서 정상
AppStream 종료 경로를 탔다면 `cleanupAppStreamSession` 의 `AppMenuRegistry.shared.prune(pid:)`
로 해당 PID 의 매핑이 회수된다. 기존 보고서의 "non-AppStream 메뉴 조회 경로" 표현은
과했다.

### 정리 경로
- `prune(pid:)` 는 `ProjectionChannel+appman.swift` 의 `cleanupAppStreamSession` 에서
  호출된다.
- `ProjectionChannel.destroy()` 는 활성 AppStream 세션이 있으면 `cleanupAppStreamSession` 을
  호출하므로 정상 채널 종료에서도 pid prune 이 수행된다.
- `removeAll()` 은 코드 어디에서도 호출되지 않는다.
- `DesktopContextManager.pruneSubscriptions(forTerminatedPID:)` 는 menu/contextMenu 구독만
  지우고 `AppMenuRegistry` 는 건드리지 않는다. AppStream app-termination 구독이 정상 동작하면
  `cleanupAppStreamSession` 이 prune 하지만, 채널 상태가 이미 꼬였거나 AppStream 외 경로가
  추가되면 안전망이 없다.

### 누적이 발생하는 시나리오
1. **컨텍스트 메뉴 open/close 반복**:
   `dispatchContextMenuOpened(element:)` 는 popup root 를 `AccessibilityTreeBuilder` 로
   스냅샷하면서 transient AXUIElement 들을 등록한다. `dispatchContextMenuClosed(element:)` 는
   `lookup(element:pid:)` 로 menuId 를 찾아 `nodeRemoved` 이벤트만 보내고, 해당 popup subtree 의
   UUID/AXUIElement 매핑은 제거하지 않는다. 같은 앱의 AppStream 세션이 오래 유지되면
   우클릭 메뉴를 열고 닫을 때마다 새 transient entry 가 pid prune 전까지 남을 수 있다.
2. **메뉴 재스냅샷 (debounce 200 ms)**:
   `setupMenuRefreshPipeline` 이 메뉴 노티마다 `snapshotMenuBar(depth: 2)` 를 호출한다.
   CFEqual 기반 재사용 (`AXElementKey`) 으로 안정적인 메뉴바 노드는 idempotent 이지만,
   사용자가 한 번도 펼치지 않은 nested submenu 가 lazy-populate 되거나, 앱이 동적으로 메뉴
   항목을 추가하면 새 entry 가 누적된다. 이는 dispatch action 을 위해 의도된 캐시지만 상한이
   없다.
3. **종료 PID safety gap**:
   `NSWorkspace.didTerminateApplicationNotification` 핸들러는 `stopMonitoring(pid:)` 와
   `pruneSubscriptions(forTerminatedPID:)` 만 호출한다. AppStream cleanup 이 실행되지 못한
   경우 종료된 PID 의 AXUIElement 매핑이 registry 에 남는다.

### 영향
한 번의 메뉴 항목당 약 ~80 bytes (UUID 16B + 두 dict entry overhead) 수준이라
즉각 OOM 을 일으키는 규모는 아니지만, 다음 두 조건이 겹치면 단조 증가가 명확히
관측된다:
- 장시간 AppStream 세션에서 popup/context menu 를 자주 열고 닫는 패턴
- 메뉴가 풍부하고 동적 항목을 많이 만드는 앱(Xcode, Safari, Electron 앱 등)
- AppStream cleanup 이 누락된 비정상 disconnect/상태 꼬임

### 권장 조치
- **A. 컨텍스트 메뉴 subtree prune**: popup open 시 반환한 `AccessibilityNode` 의 전체
  descendant UUID 집합을 root menuId 와 함께 기록하고, popup close 이벤트를 보낸 직후
  해당 UUID 들을 `AppMenuRegistry` 에서 제거한다. `DispatchActionRequest` 가 늦게 도착하면
  `Unknown targetNodeId` 로 실패시키는 것이 이미 닫힌 popup 에 액션을 수행하는 것보다 안전하다.
- **B. 종료 PID prune 훅**: `pruneSubscriptions(forTerminatedPID:)`
  (`DesktopContextManager.swift:1909`) 에 `AppMenuRegistry.shared.prune(pid:)` 를
  추가. 이미 동일한 위치에서 `menuEventSubscriptions` / `contextMenuEventSubscriptions`
  를 prune 하므로 자연스러운 위치다.
- **C. shutdown safety net**: `DesktopContextManager.shutdown()` 에서
  `AppMenuRegistry.shared.removeAll()` 을 호출한다.
- **D. 진입점 단순화**: `register()` 호출이 빌더 내부에서만 일어나도록 보장하고,
  AppSession 별로 entry 수에 soft cap (예: 5,000) 을 두어 초과 시 LRU eviction.
  단, in-flight `DispatchActionRequest` 가 evicted UUID 를 참조하면 실패할 수
  있어 trade-off 가 있음.

---

## 3. `DesktopContextManager.shared.shutdown()` 가 외부에서 호출되지 않음

### 현상
- `DesktopContextManager` 는 `shared` 싱글턴이다 (`line 1128`).
- `deinit` 에서 `shutdown()` 을 호출하지만 (`line 1161-1163`), 싱글턴이므로
  `deinit` 은 프로세스 종료 전까지 fire 되지 않는다.
- 코드베이스 전역 grep 결과 `DesktopContextManager.shared.shutdown()` 직접 호출은
  존재하지 않는다 (`server.shutdown()` 들은 `NoctilucaServer` / `SiriusServer` 의
  것이다).

### 영향
- `workspaceObservers` (launch/terminate/activate) 는 프로세스 종료 시까지 등록 상태
  유지 → 정상 종료 시 OS 가 자동 회수하므로 실질 누수는 아님.
- `activeSessions` 의 `AppSession` 들은 NSWorkspace 의 termination notification 으로
  하나씩 `stop()` 되긴 하지만, 종료 알림이 누락되거나 강제 종료 시 +1 retain 이
  남는다 (항목 #6 참조).
- 서버 stop 후 다시 startup 하는 경로에서는 `DesktopContextManager` 가 이전 세션과
  workspace observer 를 그대로 들고 있을 수 있다. `NoctilucaServer.shutdown()` 은 현재
  `NocFSAccessHost.shared.shutdownAndUnmount()` 와 `server.shutdown()` 만 수행한다.

### 권장 조치
- `NoctilucaServer.shutdown()` (`server/NoctilucaServer.swift:280` 부근) 에서
  `DesktopContextManager.shared.shutdown()` 를 한 번 호출하도록 명시적 wiring.
  서버 stop 시 (트레이 메뉴의 "서버 중지" 포함) AX/Workspace 자원이 명시적으로
  정리되어 재시작 사이의 누수 가능성을 차단할 수 있다.
- 단, 현재는 `shared.deinit` 외에 직접 호출이 없어 *재시작 시점* 의 정리 누락은
  관측되지 않는다. 우선순위는 낮다.

---

## 4. 종료된 PID 의 윈도우/앱 이벤트 구독 미정리

### 현상
`pruneSubscriptions(forTerminatedPID:)` 의 docstring 은 의도를 명확히 한다:

> window subscriptions 은 filter 기반(AND/OR/regex 조합 가능)이라 이 prune 의
> 대상이 아니며, app event subscriptions 는 bundleId 가 같은 앱이 재실행될 수 있어
> 보존한다.

즉, **menu / contextMenu 구독만 PID-키 prune 대상이며**, window/app 구독은 의도적
보존이다.

### 영향
- `WindowEventSubscription.filter` 가 `.pid(uint)` 인 경우 — 해당 pid 의 앱이 종료
  되면 `WindowChangedEvent.eventType=closed` 가 한 번 발화된 뒤 더는 매칭되지
  않는다. 구독 entry 는 남지만 dispatch loop 의 매칭 비용만 추가됨 (메모리 약 100B).
- AppStream 경로는 `bundleIdFilter` 기반 `appEventSubscriptions` 가
  `cleanupAppStreamSession` 으로 명시 해제되므로 영향 없음.
- 단, 항목 #1 처럼 구독이 채널 destroy 에서 누락되어 이미 stale 상태라면, 종료된 PID 의
  window subscription entry 도 계속 남는다. 이 경우 AppSession 은 앱 종료로 정리되지만
  subscription dictionary 는 계속 증가할 수 있다.

### 권장 조치
- 현 상태 유지가 의도이며 leak 보다는 design choice. AppStream 외에 PID-필터 윈도우
  구독을 사용하는 신규 경로가 생기면 caller 측에서 명시적 unsubscribe 가 필요함을
  AGENTS.md 에 명기.

---

## 5. SkyLight 사설 API 의 +1 반환에 대한 ARC 동작 — **확인 필요**

### 배경
`getSkyLightWindowInfo(for:)` (`DesktopContextManager.swift:68`) 는
`fetchWindowList` / `globalWindowList` 의 매 윈도우마다 호출되며, refresh 주기
(50 ms 디바운스) + 사용자 조작 시 빈도가 매우 높다.

내부적으로 다음 두 Copy/Query 계열 사설 API 를 사용한다:

```swift
let query = SkyLightPrivate.SLSWindowQueryWindows?(connection, ...)   // CFTypeRef?
let iterator = SkyLightPrivate.SLSWindowQueryResultCopyWindows?(query) // CFTypeRef?
```

이 함수들은 Gesu 매크로 (`Gesu/Sources/GesuMacros/PrivateFunctionMacro.swift`) 가
생성한 `@convention(c)` 함수 포인터를 `dlsym` 으로 바인딩해 호출된다.

### 문제
Apple Core Foundation 의 *Create Rule* (이름에 `Create` / `Copy` 가 포함된 함수는
+1 retained reference 를 반환) 은 **헤더 임포트된** 함수에 한해 Swift 컴파일러가
자동으로 인식한다. `dlsym` 으로 바인딩된 함수 포인터의 반환은:

- 정식 헤더가 없으므로 컴파일러가 *Create Rule* 을 적용하지 않는다.
- 반환 타입이 `CFTypeRef?` (= `AnyObject?`) 이므로 Swift ARC 는 "이미 retained 된
  reference 가 전달됐다" 라고 가정하는 것이 *일반적* 이지만, 이는 `@convention(c)`
  의 ABI 규약에 명시되어 있지 않다.

즉, **Swift 가 이 +1 을 자동 release 하는지 여부가 정의되지 않은 영역** 이며,
구현체/버전에 따라 leak 이 발생할 수 있다.

### 영향 (만약 leak 인 경우)
- `getSkyLightWindowInfo` 한 호출당 +2 CF 객체 (query result + iterator) leak.
- `refreshWindows()` 1회당 윈도우 N 개 × 2 = 2N 객체.
- `fetchWindowList` (`isRefreshing` 직렬화로 합쳐지지만) 정상 사용 시 분당 수십~수백
  refresh × 수십 윈도우 = 분당 수천 CF 객체 leak.
- 한 객체 크기는 작지만 (수십~수백 B), 분당 수 MB 누적 가능 → 장시간 세션에서
  명확한 메모리 증가.

### 검증 방법 (필수)
1. Instruments → Leaks instrument 로 `NoctilucaServer` 어태치.
2. 트레이 메뉴에서 서버 시작 → 클라이언트 접속 → AppStream 또는 일반 projection
   세션 활성화.
3. 약 5분간 사용자 활동 시뮬레이션 (윈도우 이동/리사이즈/앱 전환).
4. Leaks instrument 의 leaked CF objects 탭에서 `SLSWindowQueryResult*` 또는
   유사 SkyLight private type 의 backtrace 확인.
   - backtrace 가 `getSkyLightWindowInfo` 로 거슬러 올라가면 leak 확정.

### 권장 조치 (검증 후 leak 확정 시)
- 각 SkyLight Copy/Query 호출의 결과를 처음부터 `Unmanaged<...>` 로 받는 별도 바인딩을
  만든 뒤 `takeRetainedValue()` 로 Create Rule 을 명시한다. 현재 `CFTypeRef?` 로 받은 값을
  사후에 `Unmanaged.passUnretained(...).release()` 하는 방식은 Swift ARC 가 이미 관리 중인
  객체를 over-release 할 수 있어 피해야 한다. 예:

  ```swift
  typealias SLSWindowQueryWindowsRetained =
      @convention(c) (CGSConnectionID, CFArray, Int32) -> Unmanaged<CFTypeRef>?
  typealias SLSWindowQueryResultCopyWindowsRetained =
      @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?

  guard let query = SLSWindowQueryWindowsRetainedFn(connection, [windowID] as CFArray, 1)?
      .takeRetainedValue()
  else {
      return nil
  }
  guard let iterator = SLSWindowQueryResultCopyWindowsRetainedFn(query)?
      .takeRetainedValue()
  else {
      return nil
  }
  ```

  위 예시는 방향성 설명용이다. 실제 구현은 Gesu 매크로가 `retainedRet:` 같은 옵션을 받아
  `Unmanaged<T>?` function pointer 를 생성하도록 확장하는 편이 가장 일관적이다.
- `Gesu/PORTING_SPEC.md` 또는 Gesu README 에 Create/Copy 함수의 ARC 가이드 추가.
- 같은 패턴이 `SLSCopyAssociatedWindows`, `SLSCopyManagedDisplays`, `SLSCopySpacesForWindows`,
  `SLSCopyWindowProperty` 등 다수에 영향 — 일괄 점검 필요. 현재 `DesktopContextManager` 의
  hot path 에서 실제 호출되는 것은 `SLSWindowQueryWindows` /
  `SLSWindowQueryResultCopyWindows` 이다.

---

## 6. `AppSession.stop()` 누락 시 `Unmanaged.passRetained` 영구 retain

### 현상
`AppSession.setupObserver()` 는 AX 콜백 컨텍스트를 위해 self 를 +1 retain 한다:

```swift
let refCon = Unmanaged.passRetained(self).toOpaque()
self.observerRefCon = refCon
```

이 retain 은 `stop()` 에서만 release 된다:

```swift
if let refCon = observerRefCon {
    Unmanaged<AppSession>.fromOpaque(refCon).release()
    observerRefCon = nil
}
```

### 정리 경로
- 정상: `NSWorkspace.didTerminateApplicationNotification` →
  `stopMonitoring(pid:)` → `session.stop()`.
- 비정상: `shutdown()` (현재 외부에서 호출되지 않음, 항목 #3) 또는 fallthrough.

### 방어 코드
`deinit` 에 `assertionFailure("AppSession ... deallocated without stop()")` 가
박혀 있어 (`line 528-530`), DEBUG 빌드에서는 즉시 검출된다. Release 빌드에서는
no-op 이므로 leak 만 발생한다.

### 권장 조치
- 현재 패턴은 충분히 견고하다. 추가 조치는 (#3 처럼) `DesktopContextManager.shutdown()` 을
  서버 stop 경로에서 명시 호출하여, NSWorkspace 알림 누락 시에도 정리되도록 안전망을
  추가하는 정도면 충분.
- 만약 향후 `AppSession` 을 `NSWorkspace` 알림 외 경로로 생성/파괴하는 API 가 생기면,
  RAII 패턴 (`stop()` 을 `deinit` 에서 자동 호출) 으로 전환을 고려할 만하다. 단,
  현재는 +1 retain 자체가 자동 deinit 을 막고 있어 그대로는 불가능 — `axObserver` 와
  `observerRefCon` 을 별도 강참조 컨테이너에 두고 AppSession 본체는 weak 로
  들고 있는 구조로 리팩토링 필요.

---

## 7. CGWindowList 기반 매 refresh 마다의 `[CGWindowID: AXUIElement]` 맵 재구축

### 현상
`fetchWindowList()` (`line 975`) 는 호출마다 `buildAXWindowMap()` 으로 PID 단위
모든 AX 윈도우를 enumerate 한다. `globalWindowList()` (`line 1609`) 는
`buildGlobalAXWindowMaps(from:)` 로 *모든 PID* 에 대해 동일 작업을 반복한다.

### 영향
- 메모리 leak 은 없다 — 맵은 local 스코프에서 release 된다.
- 그러나 `AXUIElementCopyAttributeValue` 가 PID 마다 호출되어 (10-30 ms 수준의)
  IPC 비용이 누적. 50 ms 디바운스라도 30 ms IPC × 윈도우 수 = 쉽게 디바운스를
  초과하여 다음 refresh 가 큐잉되는 cascade 가 가능.
- 별도 문서 `docs/TODO_DESKTOPCONTEXTMANAGER_DEBOUNCING.md` 에서 이미 트래킹되고
  있는 것으로 보임 (파일명 기준).

### 권장 조치 (leak 외)
본 보고서 범위 밖. AX 결과 단기 캐시 + 차등 갱신 (현재 200 ms 메뉴 디바운스 + 50 ms
window 디바운스 외에 윈도우 맵 자체에도 TTL 캐시) 도입을 별도 작업으로 분리.

---

## 8. 사이드 노트 — 확인했으나 leak 이 아닌 항목

다음은 의심하여 정독했으나 정상으로 판단되는 항목이다:

- **AXObserver runloop source** — `stop()` 에서 `CFRunLoopRemoveSource` + AX
  notification 일괄 제거 후 `axObserver = nil`. Swift ARC 가 마지막 strong reference
  를 놓으면 AXObserver 본체는 CF 규약대로 deinit 된다. (line 543-555)
- **`CFRunLoopRemoveSource` 누락 우려** — `stop()` 에서 명시적 호출이 있다. ✅
- **`AXValueCreate` (line 678-679)** — Swift 가 CFTypeRef 로 받아 자동 release.
  ✅ Apple 헤더 임포트 경로이므로 ARC 가 인지함.
- **`CGWindowListCopyWindowInfo`** — 동일하게 헤더 기반 Create rule 적용. ✅
- **`AXUIElementCopyAttributeValue` 의 `value` outparam** — `CFTypeRef?` 로 받고
  Swift bridging 으로 release. ✅
- **NSWorkspace observer block 의 self 캡처** — `[weak self]` 명시. ✅
- **`Task { [weak self] in ... }` (init line 1155)** — `[weak self]` 명시. ✅
- **Combine `cancellables`** — `stop()` 에서 `removeAll()`. ✅
- **`debounce(...).sink { [weak self] ... }`** — 패턴 적용. ✅

---

## 우선순위 권장 조치 정리

1. **(즉시)** winman `SubscribeWindowEvents` UUID 를 `ProjectionChannelState` 에 저장하고
   channel destroy 시 unsubscribe 한다. 동시에 `DesktopContextManager` 에
   subscription-owned `AppSession` refcount 를 추가해 unsubscribe 후 불필요한 AXObserver 를
   stop 한다.
2. **(즉시, 작게 가능)** popup/context menu close 시 `AppMenuRegistry` subtree 를 prune 하고,
   `pruneSubscriptions(forTerminatedPID:)` 에 `AppMenuRegistry.shared.prune(pid:)` 를 추가한다.
3. **(검증 후 즉시)** Instruments Leaks 로 항목 #5 (SkyLight Copy/Query ARC) 확정 →
   Gesu 매크로 또는 호출부에 `Unmanaged` 명시. 본 보고서 작성 시점에서는 leak 여부가
   미확정이나, 만약 leak 이라면 가장 큰 누수 채널이다.
4. **(중기, 안전망)** `NoctilucaServer.shutdown()` 에서
   `DesktopContextManager.shared.shutdown()` 호출 — 서버 재시작 시점에 명시적 정리.
5. **(별도 작업)** 항목 #7 의 AX 맵 캐싱 — `docs/TODO_DESKTOPCONTEXTMANAGER_DEBOUNCING.md`
   에 연계.

---

## 검증을 위한 Instruments 시나리오

본 보고서를 닫기 위해 다음 시나리오로 실측 권장:

1. NoctilucaServer Debug 빌드 실행 → 트레이에서 서버 시작.
2. Instruments → Allocations + Leaks 어태치.
3. 클라이언트 (NoctilucaClient 또는 Qt) 에서 접속 후 AppStream 세션 시작
   (target: Xcode 또는 Finder — 메뉴바가 풍부한 앱).
4. 다음 액션을 약 5분 반복:
   - 호스트에서 5-10개 앱 순차 launch/quit
   - 클라이언트에서 메뉴바 expand/collapse, 우클릭 컨텍스트 메뉴 open/close
   - 윈도우 이동/리사이즈
   - `SubscribeWindowEventsRequest` 를 filter 없이 보낸 뒤 unsubscribe 없이 클라이언트
     연결을 끊기
5. Allocations 의 persistent bytes 추이 확인:
   - `AppSession`, `AXObserver`, Combine subscription 객체가 unsubscribe/disconnect 뒤에도
     남는지 확인 → 항목 #1 확정.
   - `AppMenuRegistry` 관련 NSMutableDictionary 항목이 popup close 뒤에도 단조 증가 →
     항목 #2 확정.
   - `SLSWindowQueryResult*` 류 CF object leak → 항목 #5 확정.
6. AppStream 세션 stop → 메모리 회수 여부 확인.
   - 회수되지 않으면 해당 영역 leak 의 lifetime 이 세션을 넘어선다는 의미.
