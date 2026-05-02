# NoctilucaClient 디스플레이/프로젝션 Disconnection 처리 로직 감사 보고서

> 조사 일자: 2026-04-27
> 대상: `NoctilucaClient/` (macOS/iOS 클라이언트)
> 주제: 서버 측 디스플레이가 갑자기 해제되거나 프로젝션 연결이 중단되었을 때의 클라이언트 처리 로직

---

## 1. 서버 → 클라이언트 종료 신호 (메시지/opcode)

| 메시지 | opcode | 의미 |
|---|---|---|
| `ProjectionSessionEndedEvent` | `0x8024` | 서버가 세션을 강제 종료할 때 |
| `ProjectionSessionChangedEvent` | `0x8023` | 코덱/소스 변경 |
| `DisplayChangedEvent` | `0x8047` | 디스플레이 연결/해제/변경 |

정의 위치:
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/projection_session+Sirius.swift:18`
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/displayman+Sirius.swift:18`

### VideoSessionEndReason

(`SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/projection_session+Constants.swift`)

```swift
public static let unknown            = VideoSessionEndReason(rawValue: 0)
public static let clientRequested    = VideoSessionEndReason(rawValue: 1)
public static let displayDisconnected = VideoSessionEndReason(rawValue: 2)  // 외부 모니터 분리
public static let internalError      = VideoSessionEndReason(rawValue: 3)
public static let recorderFailed     = VideoSessionEndReason(rawValue: 4)   // 캡처 세션 실패
public static let dataChannelError   = VideoSessionEndReason(rawValue: 5)
```

디스플레이가 갑자기 분리되는 경우 `displayDisconnected(2)` 또는 `recorderFailed(4)` 로 종료된다.

---

## 2. 클라이언트 측 핸들러 체인

### 2-1. ProjectionDataChannel (데이터 채널)

`NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionDataChannel.swift:87-95`

```swift
func handleError(error: any Error) async {
    continuation.yield(.error(error))
    continuation.finish()
}

func handleStreamClose() async {
    continuation.yield(.closed)
    continuation.finish()
}
```

데이터 채널이 닫히면 `.closed` 또는 `.error(error)` 이벤트를 `AsyncStream` 에 yield 하고 스트림을 종료한다.

### 2-2. ProjectionChannel (제어 채널)

`NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionChannel.swift:175-192`

```swift
func handleError(error: any Error) async {
    logger.warning("ProjectionChannel error: \(error)")
    await cancelAllPending(with: error)
    continuation.finish()
}

func handleStreamClose() async {
    logger.info("ProjectionChannel stream closed")
    await cancelAllPending(with: ProjectionChannelError.channelClosed)
    continuation.finish()
}
```

`cancelAllPending(with:)` 는 다음을 모두 호출한다:
- `cancelAllPendingSessions`
- `cancelAllPendingRequests`
- `cancelAllPendingAudioSessionRequests`
- `cancelAllPendingDisplayTransactions`

### 2-3. 서버 개시 세션 종료 이벤트 핸들러

`NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionChannel+Session.swift:241-261`

```swift
func handleProjectionSessionEndedEvent(_ event: ProjectionSessionEndedEvent) async {
    guard let session = await state.removeSession(identifier) else { ... }

    // sendStopRequest: false — 서버가 이미 종료했으므로 stop 요청 미전송
    try await session.stop(sendStopRequest: false)

    continuation.yield(.sessionDestroyed(identifier, reason: event.reason, message: event.message))
}
```

### 2-4. ProjectionSession.stop()

`NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionSession.swift:538-567`

실행 순서:
1. `.projectionWillStop` 이벤트 yield
2. `jitterBuffer?.stop()`
3. `performanceReporter?.stop()`
4. `decoder?.stop()` — VTDecompressionSession 등 디코더 정리
5. `dataChannelConsumerTask?.cancel()` — 수신 루프 중단
6. `.projectionStopped` yield → `continuation.finish()`
7. `dataChannel.handle.close()` — QUIC 스트림 닫기

(`sendStopRequest=false` 이므로 `StopProjectionRequest` 는 전송하지 않음)

### 2-5. Subscription 정리

`NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionSessionSubscription.swift:82-103`

```swift
func invalidate() {
    Task {
        await session.unregisterDisplayLayer(layer)
        if let metalRenderer { await session.unregisterMetalVideoRenderer(metalRenderer) }
        if let canvasR      { await session.unregisterCanvasRenderer(canvasR) }
    }
    metalVideoRenderer = nil
    canvasRenderer     = nil
    ticket.release()
}
```

`displayLayers`, `metalVideoRenderers`, `canvasRenderers` dict 는 `ProjectionSession` actor 내부에 격리되어 있으며, unregister 후 더 이상 렌더링 콜백이 발생하지 않는다.

### 2-6. RemoteSession 레이어

`NoctilucaClient/NoctilucaClient/core/state/RemoteSession+Projection.swift:200-207, 469-472`

`.sessionDestroyed` 이벤트 처리:

```swift
case .sessionDestroyed(let sessionID, let reason, let message):
    projectionSessions.removeValue(forKey: sessionID)
    projectionSessionReferences.removeValue(forKey: sessionID)
    unsubscribeSessionEvents(sessionID)
    if projectionSessions.isEmpty { degradationNotice = nil }
    notifySessionFailure(reason: reason, message: message)
```

```swift
private func notifySessionFailure(reason: VideoSessionEndReason, message: String?) {
    self.sessionError = ProjectionSessionFailureInfo(reason: reason, message: message)
    logger.error("Projection session failure: reason=\(reason.rawValue), message=\(message ?? "(nil)")")
}
```

`sessionError` 는 `@Observable` 로 선언된 `Projection` 클래스의 `@MainActor` 격리 프로퍼티.

### 2-7. DisplayChangedEvent 처리

`NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionChannel+displayman.swift:72-75`

```swift
func handleDisplayChangedEvent(_ event: DisplayChangedEvent) async {
    await displayLayoutManager.consumeDisplayChangeEvent(event)
}
```

`DisplayLayoutManager.consumeDisplayChangeEvent()` (`DisplayLayoutManager.swift:40-51`):
- `.disconnected` → `displayLayouts.removeValue(forKey: displayID)`
- `.connected` / `.modified` / `.becamePrimary` → 업데이트

---

## 3. 전체 흐름 요약도

```
[서버] 디스플레이 분리
  ↓ ProjectionSessionEndedEvent { reason: .displayDisconnected }   (0x8024)
  ↓ DisplayChangedEvent { eventType: .disconnected }               (0x8047)

[클라] ProjectionChannel.handleFrame()
  ├─ .projectionSessionEndedEvent
  │   → handleProjectionSessionEndedEvent()
  │       → state.removeSession()
  │       → session.stop(sendStopRequest: false)
  │           → decoder?.stop()                  (VT 세션 해제)
  │           → dataChannelConsumerTask.cancel()
  │           → dataChannel.handle.close()
  │       → yield(.sessionDestroyed)
  │           → RemoteSession.Projection.handleEvent
  │               → projectionSessions 제거
  │               → sessionError 설정 ★ (UI 반응은 비활성화 — §4 참조)
  │
  └─ .displayChangedEvent
      → displayLayoutManager.consumeDisplayChangeEvent()
          → displayLayouts 에서 displayID 제거
```

---

## 4. 미구현 / 비활성화된 부분 (중요)

| 위치 | 문제 |
|---|---|
| `NoctilucaClient/NoctilucaClient/core/ui/main/MainWindowRemoteSessionView.swift:153-162` | `sessionError` 감지 후 subscription 을 invalidate 하는 코드가 **주석 처리됨**. TODO: "어떤 세션에 대한 에러인지 구분이 안 되니까, 다른 디스플레이로 전환했을 때 그냥 꺼짐" — 즉 디스플레이 분리 시 **UI 가 사용자에게 알리지 않고, subscription 도 살아있는 상태로 남음** |
| `NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionChannel+displayman.swift:101-131` | `handleDebouncedDisplayChange()` 가 구현되어 있지만 **호출되지 않음**. 디스플레이 변경 시 자동 재시작 로직이 비활성화됨 (`createSession()` 호출부도 주석 처리) |
| `NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionChannel+Session.swift:169` | `createAudioSession()` 반환 타입이 `void` 인데 `AudioProjectionSession` 을 반환해야 한다는 TODO |
| `NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionSession.swift:34` | `projectionStopped` 이벤트에 reason 이 빠져 있음 (TODO) |
| `NoctilucaClient/NoctilucaClient/.../NoctilucaClient+Main.swift:37-40` | 초기 자동 세션 생성이 주석 처리 ("디스플레이 없는 컴퓨터에서 터질 수 있다" FIXME) |
| `NoctilucaClient/NoctilucaClient/core/state/RemoteSession+Projection.swift:376` | 멀티 디스플레이 해상도가 다를 때 처리 미결 TODO |
| `NoctilucaClient/NoctilucaClient/core/feature/projection/ProjectionChannel+displayman.swift:80` | `fetchPrimaryDisplayID()` 매번 새로 요청, 캐싱 없음 FIXME |

### 주석 처리된 UI 반응 코드 (참고)

`MainWindowRemoteSessionView.swift:153-162`

```swift
/*
 // TODO: 어떤 세션에 대한 에러인지 구분이 안되니까, 다른 디스플레이로 전환했을 때 그냥 꺼짐
.onReceive(projection.$sessionError) { error in
    if error != nil {
        subscription?.invalidate()
        subscription = nil
    }
}
 */
```

---

## 5. 오디오 vs 비디오 차이

오디오는 **자동 재시작이 구현되어 있다** — `RemoteSession+Projection.swift:432-466`:

- `audioSessionDestroyed` 이벤트 시 `attemptAudioAutoRestart()` 호출
- 최대 3회 재시도, 지수 백오프 (1s / 2s / 4s)

**비디오는 자동 재시작 없음.** 디스플레이가 동일 ID 로 재연결된 경우에도 클라이언트는 새 세션을 만들지 않는다.

---

## 6. AppStream (SingleWindow) 과의 처리 차이

- `SingleWindowProjectionSource` 는 SiriusKit msgdef 에 정의되어 있음
  (`SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/projection_source+Sirius.swift:61-84`)
- 그러나 NoctilucaClient (macOS/iOS) 는 항상 `EntireDisplayProjectionSource` 만 사용
  (`ProjectionChannel+Session.swift:22-27`)
- 따라서 클라이언트 측 disconnection 처리 경로에서 AppStream 차이는 **없음**
- (CLAUDE.md 명시: AppStream 은 영구 experimental 상태)

---

## 7. 결론 및 권장 후속 작업

### 백엔드 흐름 (정리 잘 되어 있음)

서버에서 종료 신호를 받아 디코더 / QUIC 스트림 / 세션 state 까지 정리하는 흐름은 정상적으로 구현되어 있다.

### 가장 큰 갭

1. **UI 반응이 통째로 주석 처리됨** — 사용자에게 "디스플레이가 끊겼다" 는 사실이 노출되지 않는다.
2. **비디오 자동 재시작이 부재** — 오디오와 달리 재시작 메커니즘이 없다.

### 권장 후속 작업

1. `MainWindowRemoteSessionView.swift:153-162` 의 주석을 풀되, **세션 ID 매칭** 으로 해당 디스플레이의 subscription 만 invalidate 되도록 개선. (현재 무조건 invalidate 시 다른 디스플레이로 전환할 때도 화면이 꺼지는 문제가 있음 — 기존 TODO 의 사유)
2. 비디오 세션에 대해서도 `attemptAudioAutoRestart()` 와 유사한 자동 재시작 (디스플레이 ID 가 다시 살아난 경우 한정) 도입 검토.
3. `handleDebouncedDisplayChange()` 활성화 여부 결정 — 활성화한다면 호출 지점과 세션 재생성 정책을 명확히 정의 필요.
4. `ProjectionSession.projectionStopped` 이벤트에 `VideoSessionEndReason` 전달하도록 시그니처 보강 (UI 알림 메시지 차별화에 필요).
