# NoctilucaServer — Channel v2 마이그레이션 룰

> **대상**: NoctilucaServer(macOS) 서버 앱의 모든 `Channel` / `FeatureProvider` 구현체
> **기준 커밋**: SiriusKit `436c6f9` — "siriuskit/channel: Channel을 프로토콜로 재설계 및 ChannelHandle 도입"
> **스코프**: 서버 앱의 마이그레이션. 대표 사례로 `feature/projection` 전체를 다룬다.
> **비-스코프**: `Recorder`/`Encoder` 프로토콜 자체의 본격 Sendable 적합화(`Sendable` 표식 한 줄 추가는 허용), `ChannelEventCompatBridge`의 궁극적 제거, 클라이언트 앱 마이그레이션.

---

## 1. 배경과 목적

### 1.1. 436c6f9 커밋 요약

SiriusKit의 `Channel` 레이어가 "base class 상속" 구조에서 "프로토콜 + handle composition" 구조로 재설계되었다.

**이전(before)**
- `Channel`은 `open class`였고, 내부는 `@unchecked Sendable`.
- 구현체는 `handleFrame` / `handleStreamClose` / `handleStreamError` 를 `override`로 제공.
- 프레임 송신은 `sendNonBlocking(...)`, `send(opcode:message:)` 같은 상속 메서드를 직접 호출.
- 초기화자 시그니처:
  ```swift
  required init(using streamHolder: StreamHolder,
                identifier: ChannelIdentifier,
                direction: ChannelDirection)
  ```
- `FeatureProvider.createChannel`은 streamHolder를 인자로 받아 직접 `init`을 호출.

**이후(after)**
- `Channel`이 `public protocol Channel: AnyObject, Sendable`.
  - Requirement: `var handle: ChannelHandle { get }`, `init(handle: ChannelHandle)`.
- 실제 송수신/라이프사이클은 `ChannelHandle` 프로토콜(구현체 `ChannelHandleImpl`)이 담당.
- `ChannelHandle`은 `AsyncStream<ChannelEvent>` (`.ready / .frameReceived / .error / .closed`)를 노출.
- 송신 API는 모두 `handle.send(opcode:message:)` / `handle.send(nonblocking:)` / `handle.send(frame:)` 계열.
- activation 이전 송신은 `ChannelHandleImpl`이 버퍼링 → `activate()` 시 순서대로 drain.
- `ChannelEventCompatBridge<Consumer>`: `~Copyable, Sendable` struct. `init(consumer:handle:)`이 `Task.detached`로 `handle.events`를 구독하여 `ChannelEventConsumer`의 4개 메서드로 라우팅. `deinit`에서 task cancel.
- `ChannelEventConsumer` 프로토콜(`AnyObject, Sendable`): `handleChannelReady`, `handleFrame`, `handleError`, `handleStreamClose` 4종 async 메서드.
- `FeatureProvider`가 `AnyObject, Sendable`로 바뀌고, 시그니처가:
  ```swift
  func createChannel(for feature: SiriusFeature,
                     handle: ChannelHandle,
                     args: [String]) async throws -> ChannelCreationResult
  ```
- `ChannelManager`가 `ChannelHandleImpl`을 직접 생성해 `FeatureProvider`에 넘긴다. `handle.activate()` 호출 책임도 `ChannelManager`가 진다.
- `MainChannel`이 참조 구현(reference implementation).

### 1.2. 이 문서의 스코프와 비-스코프

**스코프**
- 서버 앱의 모든 `Channel` / `FeatureProvider` 구현체를 v2 API로 옮기는 규칙.
- Session류(`ProjectionSession`, `AudioProjectionSession`)의 `actor` 승격.
- Subscription류(`CursorEventSubscription`, `DisplayEventSubscription`)의 Sendable 적합화.
- `ScreenRecorderDelegate` / `AudioRecorderDelegate` / `ProjectionSessionDelegate` 같은 **내부 delegate 프로토콜에 `Sendable` 표식 1줄 추가** (actor에서 self를 delegate로 넘기기 위한 최소 타협).
- **클라이언트 앱의 HIDIO 경로**: `HIDIOChannel` / `HIDIOController` / `NoctilucaFeatureProvider` 의 v2 마이그레이션 룰. 클라이언트 마이그레이션 룰 일반은 Section 13 을 참조한다.

**비-스코프**
- `Recorder` / `Encoder` 프로토콜 본체의 실질적 Sendable 적합화 (이벤트 구조 교체, delegate → AsyncStream 전환 등) — 별도 후속 작업.
- `FrameDropController`, `FrameQueue` 등의 동시성 정식화 — actor 내부로 '격납'만 하고 정식 감사는 후속.
- `ChannelEventCompatBridge`를 걷어내고 `for await event in handle.events` 직접 구독으로 전환 — 향후 별도 단계.
- **클라이언트 앱의 남은 채널 마이그레이션** (Projection / ProjectionData). HIDIO, Clipboard, Transfer 등은 선행 작업으로 마이그레이션이 완료되었다. 나머지 채널은 후속 PR에서 같은 룰을 적용해 이식한다.

---

## 2. 용어 정리

- **v1**: 436c6f9 이전의 `Channel` base class 기반 구조.
- **v2**: 436c6f9 이후의 `Channel` 프로토콜 + `ChannelHandle` 기반 구조.
- **Handle**: `ChannelHandle` 프로토콜. 내부 구현체는 `ChannelHandleImpl` (SiriusKit package 레벨).
- **CompatBridge**: `ChannelEventCompatBridge<Consumer>`. v1 스타일의 handleXxx 훅을 v2 `AsyncStream<ChannelEvent>` 위에서 재현해 주는 어댑터.
- **Consumer**: `ChannelEventConsumer` 프로토콜 채택자. 채널 본인이 일반적 선택.
- **Session류**: `ProjectionSession`, `AudioProjectionSession` 등 채널의 실제 파이프라인 실행을 담당하는 비-채널 객체.
- **Subscription류**: `CursorEventSubscription`, `DisplayEventSubscription`. 외부 이벤트 소스를 채널로 중계하는 어댑터.

---

## 3. 공통 룰 (General Rules)

> 각 룰은 "실무자가 파일을 열고 기계적으로 적용할 수 있는 변환"을 목표로 한다.

### Rule A — `final class` + `Channel` 프로토콜 채택

**규칙**
- `class Foo: Channel`의 모든 `override`는 사라진다.
- 선언은 다음 형태로 고정:
  ```swift
  final class FooChannel: Channel, ChannelEventConsumer {
      let handle: ChannelHandle
      // ...
  }
  ```
- `final`로 고정하여 v1 습관(서브클래싱을 통한 확장)을 차단한다.

**Before**
```swift
class ProjectionChannel: Channel {
    override var serviceClass: ServiceClass { .userInput }
    // ...
}
```

**After**
```swift
final class ProjectionChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    // serviceClass 는 handleChannelReady() 시점에 handle.setServiceClass 로 이관 (Rule F)
}
```

**안티패턴**
- `final`을 빼고 기본 class 로 두기 — 서브클래스에서 v1 습관 부활.
- `ChannelEventConsumer` 없이 채널마다 제각각 `for await event in handle.events` 루프를 만드는 것 — 일관성 붕괴. CompatBridge 사용을 기본값으로 (Rule D).

---

### Rule B — `init(handle:)` 시그니처로 전환

**규칙**
- `required init(using streamHolder:, identifier:, direction:)` 제거.
- 반드시 다음 시그니처:
  ```swift
  init(handle: ChannelHandle) { ... }
  ```
- `identifier`/`direction`/`feature` 가 필요하면 `handle.identifier`, `handle.direction`, `handle.feature` 로 읽는다.
- `assert(handle.direction == .remote)` 같은 검증은 그대로 유지 가능.

**Before**
```swift
required init(using streamHolder: StreamHolder,
              identifier: ChannelIdentifier,
              direction: ChannelDirection) {
    super.init(using: streamHolder, identifier: identifier, direction: direction)
    assert(direction == .remote, "ProjectionChannel must be opened from remote side")
    // Combine sink 설정 ...
}
```

**After**
```swift
init(handle: ChannelHandle) {
    self.handle = handle
    assert(handle.direction == .remote,
           "ProjectionChannel must be opened from remote side")

    // events 스트림 / continuation 같은 let 필드 초기화
    // CompatBridge 연결 (Rule D)
    // state actor 를 통한 Combine sink 설치 (Rule J)
}
```

**안티패턴**
- `init(handle:)` 안에서 `handle.activate()` 호출 — activate 는 `ChannelManager` 의 책임. 채널 측이 호출하면 이중 활성화 / race.

---

### Rule C — `override handleFrame/handleStreamClose/handleStreamError` 제거 → `ChannelEventConsumer` 구현

**규칙**
- v1 의 4개 override를 제거하고 다음 4개의 `ChannelEventConsumer` async 메서드를 구현한다:
  ```swift
  func handleChannelReady() async
  func handleFrame(frame: SiriusFrame) async throws
  func handleError(error: Error) async
  func handleStreamClose() async
  ```
- 호출 컨텍스트는 **CompatBridge 내부의 `Task.detached`**. `@MainActor` 가정은 금지.
- 옛 `handleStreamClose` / `handleStreamError` 의 `Task { [weak self] in await self?.destroy() }` 패턴은 단순히 `await destroy()` 한 줄로 대체 가능 (이미 async context).

**Before**
```swift
override func handleFrame(frame: SiriusFrame) async throws {
    switch frame.opcode { ... }
}
override func handleStreamClose() {
    super.handleStreamClose()
    Task { [weak self] in await self?.destroy() }
}
override func handleStreamError(error: any Error) {
    super.handleStreamError(error: error)
    Task { [weak self] in await self?.destroy() }
}
```

**After**
```swift
func handleChannelReady() async {
    // 대부분 비워 두거나 setServiceClass 호출 (Rule F)
}
func handleFrame(frame: SiriusFrame) async throws {
    guard frame.isValid() else { throw ChannelError.invalidFrame }
    switch frame.opcode { ... }
}
func handleError(error: any Error) async {
    await destroy()
}
func handleStreamClose() async {
    await destroy()
}
```

**안티패턴**
- `handleStreamClose` 내부에서 `try await handle.close()` 재호출 — 이미 닫힌 stream을 또 닫는 꼴.
- `handleFrame` 내부 throw 을 swallow — v2 CompatBridge는 현재 swallow + TODO 로깅이므로, 가능한 한 throw 를 보존해 향후 로깅 보강 여지를 남긴다.

---

### Rule D — `ChannelEventCompatBridge` 소유 패턴

**규칙**
- 모든 Channel 구현체는 `ChannelEventCompatBridge<Self>` 인스턴스를 **정확히 하나** 소유한다.
- 필드 선언은:
  ```swift
  nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<FooChannel>!
  ```
- `init` 의 **마지막 줄**에서 `self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)` 로 한 번만 대입한다.

**표준 형태**
```swift
final class FooChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle

    // 외부 노출용 이벤트 스트림이 있는 경우 (옵션)
    nonisolated(unsafe) let events: AsyncStream<FooChannelEvent>
    private let continuation: AsyncStream<FooChannelEvent>.Continuation

    // CompatBridge: init 마지막에 self 를 넘겨 생성하므로
    // nonisolated(unsafe) var + force-unwrap 로 선언
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<FooChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle

        var contLocal: AsyncStream<FooChannelEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont in
            contLocal = cont
        }
        self.continuation = contLocal

        // 마지막에 한 번만 대입. 이후 수정하지 않는다.
        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }
}
```

**왜**
- `ChannelEventCompatBridge` 는 `~Copyable` 이므로 일반 `let` 필드 초기화 순서상 "self 를 consumer 로 넘기면서 마지막에 한 번만" 대입하려면 force-unwrap var 패턴이 필요하다.
- `nonisolated(unsafe)` 는 Rule I에서 예외 허용되는 두 패턴 중 하나.
- 동일 `handle` 의 `events` `AsyncStream` 은 unicast이므로 CompatBridge를 2개 붙이면 안 된다 — **채널당 정확히 1개**.

**안티패턴**
- `var channelEventCompatBridge: ChannelEventCompatBridge<Self>?` (일반 Optional var) — Sendable 적합화가 깨진다. 반드시 `nonisolated(unsafe)` 가 필요.
- `lazy var` 로 지연 생성 — `Task.detached` 기동 타이밍이 비결정적.

---

### Rule E — `send`/`sendNonBlocking` → `handle.send` 위임

**규칙**
- 모든 송신은 `self.handle.send(...)` 네 가지 변형 중 하나로 치환:
  - `try await handle.send(opcode:message:)`
  - `handle.send(nonblocking opcode:message:)`
  - `try await handle.send(frame:)`
  - `handle.send(nonblocking frame:)`
- 채널 편의 메서드(`sendCursorPositionEvent` 등)는 그대로 유지하되 내부만 교체.

**Before**
```swift
func sendCursorPositionEvent(_ state: CursorState) async throws {
    sendNonBlocking(opcode: .cursorEvent,
                    message: CursorEvent(event: .moveEvent(...)))
}
try await send(opcode: .projectionSessionCreatedEvent, message: ...)
```

**After**
```swift
func sendCursorPositionEvent(_ state: CursorState) async throws {
    handle.send(nonblocking: .cursorEvent,
                message: CursorEvent(event: .moveEvent(...)))
}
try await handle.send(opcode: .projectionSessionCreatedEvent,
                      message: ...)
```

**왜**
- `Channel` 은 프로토콜이므로 `send` 기본 구현을 상속받을 길이 없다.
- `handle` 에 위임하면 pre-activation 버퍼링, data-rate 카운터, atomic fast-path 등 v2의 부가 기능을 자동 획득.

**안티패턴**
- `Channel` extension 에 `send(...)` default 구현을 넣기 — 가능하지만 handle 호출과 중복. 초기에는 피한다.
- activation 이전에 `handle.stream.write(...)` 직접 호출 — handle 이 이미 버퍼링을 제공한다.

---

### Rule F — `serviceClass` override → `handle.setServiceClass` 호출

**규칙**
- `override var serviceClass` 는 불가. 대신 **적절한 시점**에 `await handle.setServiceClass(_:)` 를 호출한다.
- 적절한 시점은 `handleChannelReady()` 표준. CompatBridge 가 이미 async 컨텍스트를 제공한다.
- 값은 채널당 상수로 보관:
  ```swift
  private static let defaultServiceClass: ServiceClass = .userInput
  ```

**Before**
```swift
class ProjectionChannel: Channel {
    override var serviceClass: ServiceClass { .userInput }
}
```

**After**
```swift
final class ProjectionChannel: Channel, ChannelEventConsumer {
    private static let defaultServiceClass: ServiceClass = .userInput

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }
}
```

**안티패턴**
- `init(handle:)` 내부에서 `Task { await handle.setServiceClass(...) }` — activation 전에 실행될 수 있고 Task 기동이 불필요.
- 반복 호출 — 1회로 충분.

---

### Rule G — 채널 자체의 가변 상태는 state actor로 분리

**규칙**
- 채널 클래스 본체의 가변 상태는 가능한 한 **state actor로 이동**한다.
- **예외 (고빈도 전송 채널)**: `TransferChannel`처럼 64KB 단위 청크 전송 등으로 `handleFrame`이 매우 빈번하게 호출되는 경우, Actor Hop 오버헤드를 방지하기 위해 가변 상태를 캡슐화한 **`@unchecked Sendable` 클래스 내부에 `NSLock` (또는 `OSAllocatedUnfairLock`)을 사용하는 패턴**을 허용한다.
- **예외 (미디어 파이프라인 class)**: `ScreenRecorder` / `AudioRecorder` / `VideoEncoder` / `AudioEncoder` 프로토콜의 구현체와 같은 **외부 미디어 프레임워크(ScreenCaptureKit, VideoToolbox, AVFoundation, libwebp 등) 래퍼 class**는 `@unchecked Sendable` 을 허용한다. 사유는 두 가지다:
  1. 이들 구현체는 내부에서 `DispatchQueue.sync` (`workerQueue`) 기반으로 가변 상태를 직렬화하고 있어 실제 thread-safety 가 확보되어 있다.
  2. 호출자(`ProjectionSession` / `AudioProjectionSession` actor) 가 이미 actor 격리 하에서 순차 호출을 보장한다.
  - actor 로 승격하는 정식 적합화는 이들 프로토콜/구현체의 메서드 시그니처(throws/sync 호출, NS* delegate 대응) 가 함께 바뀌어야 하므로 비용이 크다. 본 마이그레이션의 범위를 벗어난다.
  - 구현체의 `final class ... @unchecked Sendable` 선언 위에는 **반드시 근거 주석**을 남긴다 (예: "문서 Rule G 확장: 미디어 파이프라인 class 예외").
  - 후속 과제: delegate → `AsyncStream<Event>` 전환 또는 actor 승격으로 `@unchecked` 제거.
- `ProjectionChannel` 의 기존 `ProjectionChannelState` 가 레퍼런스 모델.
- 채널 본체에는 다음 범주만 남긴다:
  - `let handle: ChannelHandle`
  - `let state: SomeStateActor` (또는 여러 개)
  - `let logger: SiriusLogger` 같은 immutable 의존성
  - `nonisolated(unsafe) let events: AsyncStream<...>` + `private let continuation` (외부 노출 이벤트가 있는 경우)
  - `nonisolated(unsafe) private var channelEventCompatBridge: ...!`

**안티패턴**
- 모든 필드를 `nonisolated(unsafe) var` 로 쏟아붓기 — Rule I 금지선 위반.
- class 를 `@unchecked Sendable` 로 퉁치기 — 금지.

---

### Rule H — `clientSession` 접근은 기존 확장 그대로

**규칙**
- `SiriusKit/Sources/SiriusKit/server/Channel+getClientSession.swift` 에 이미 v2 friendly 로 작성되어 있다:
  ```swift
  public extension Channel {
      var clientSession: ClientSession? {
          guard let session = self.handle.asImpl.session as? ClientSession else { return nil }
          return session
      }
  }
  ```
- 호출부는 `self.clientSession` 그대로 유지.
- 이 property 는 computed 이고 weak/unowned chain 으로만 접근하므로 별도 격리가 필요하지 않다.

**안티패턴**
- extension 내부의 코드를 여러 채널에서 복제 — 중복.
- `clientSession` 을 init 에서 강한 참조로 캐싱 — retain cycle.

---

### Rule I — Sendable 적합 기본 형태

**규칙**
- `@unchecked Sendable`: **금지**. (단, Rule G의 고빈도 채널 Lock 패턴 예외 허용)
- `nonisolated(unsafe)` **let**/**var**: 다음 세 가지 패턴에 한해 허용.
  1. **"init 에서 한 번 대입, 이후 불변" 패턴**
     - `AsyncStream.Continuation` 과 쌍을 이루는 `let events` / `let continuation` 필드 (예: `MainChannel.events`).
     - 이유: `AsyncStream.init` 의 클로저가 `@escaping` 이라 var 임시 → `self.let` 대입 단계가 필요. 대입 이후 수정되지 않는다.
  2. **"`~Copyable` struct 를 init 마지막에 한 번만 대입" 패턴**
     - `channelEventCompatBridge: ChannelEventCompatBridge<Self>!` 필드.
     - 이유: Self 를 consumer 로 넘겨야 하므로 stored property 초기화 순서상 init 마지막에 대입. `~Copyable` 때문에 var 선언 불가피.
  3. **"초기화 직후 1회 설정되는 콜백" 패턴**
     - `onReady`, `onTransferStarted` 같은 클로저 프로퍼티.
     - 이유: 채널 생성과 준비 단계에서 정확히 한 번만 주입되고, 이후 수명 주기 동안 결코 변경되지 않음을 논리적으로 보장할 때.
- 위 세 가지 외 `nonisolated(unsafe)` 사용은 리뷰에서 **차단**한다.

**선언 시 주석 필수**
```swift
// init 에서 1회 대입, 이후 불변. AsyncStream.Continuation 패턴.
nonisolated(unsafe) let events: AsyncStream<FooEvent>

// ~Copyable CompatBridge; init 마지막 대입 후 수정 없음.
nonisolated(unsafe) private var channelEventCompatBridge: ChannelEventCompatBridge<Foo>!
```

**체크리스트**
- [ ] `@unchecked Sendable` 이 소스 트리에서 전부 제거되었는가?
- [ ] 모든 `nonisolated(unsafe)` 사용처가 위 두 패턴 중 하나에 해당하는가?
- [ ] 각 사용처에 "왜 안전한지" 1줄 주석이 있는가?

---

### Rule J — Combine cancellable 등 가변 상태 처리

**규칙**
- `ProjectionChannel.displayChangesCancellable` 같이 "채널 수명과 동일한 단일 Combine 구독" 은 **state actor 로 이동**한다.
- 채널 본체를 actor 로 승격하는 대안도 가능하지만, `MainChannel`이 `final class` 참조 구현을 제공하므로 **일관성 차원에서 채널 본체는 final class 유지**, 가변 상태만 actor 로 옮기는 쪽을 권장.

**Before**
```swift
final class ProjectionChannel: Channel {
    private var displayChangesCancellable: AnyCancellable?

    init(handle: ChannelHandle) {
        // ...
        self.displayChangesCancellable = DisplayLayoutManager.shared.displayChangeSubject
            .filter { $0.eventType.contains(.disconnected) }
            .sink { [weak self] event in
                Task { await self?.handleDisplayDisconnected(displayID: event.displayID) }
            }
    }
}
```

**After**
```swift
final class ProjectionChannel: Channel, ChannelEventConsumer {
    let state = ProjectionChannelState()

    init(handle: ChannelHandle) {
        self.handle = handle
        // ...
        Task { [state] in
            await state.installDisplayDisconnectSink { [weak self] displayID in
                await self?.handleDisplayDisconnected(displayID: displayID)
            }
        }
        self.channelEventCompatBridge = ChannelEventCompatBridge(consumer: self, handle: handle)
    }
}

extension ProjectionChannelState {
    func installDisplayDisconnectSink(
        _ callback: @escaping @Sendable (CGDirectDisplayID) async -> Void
    ) {
        self.displayChangesCancellable = DisplayLayoutManager.shared.displayChangeSubject
            .filter { $0.eventType.contains(.disconnected) }
            .sink { event in
                Task { await callback(event.displayID) }
            }
    }
}
```

> 주의: `DisplayLayoutManager.shared.displayChangeSubject` 가 어떤 스레드에서 값을 내보내는지 Combine publisher 스레딩 가정을 구현 시점에 재검증할 것. 위 코드는 구조만 보여 주는 pseudo.

**안티패턴**
- `nonisolated(unsafe) var displayChangesCancellable: AnyCancellable?` — Rule I 금지선 위반.

---

### Rule K — `destroy()` / `close()` 패턴

**규칙**
- `ProjectionChannel.destroy()` 의 "2-phase teardown (active → destroying → destroyed)" 는 그대로 유지.
- 호출 경로 정리:
  - `handleStreamClose()` / `handleError()` → `await destroy()` 직접 호출.
  - `ChannelManager.teardownAllChannels()` → `handle.close()` → stream close → CompatBridge 의 `handleStreamClose` 트리거 → `destroy()`.
  - 상위(`NoctilucaClientSession`) 에서 직접 `projectionChannel.destroy()` 호출도 허용.
- `destroy()` 는 **재진입 멱등**해야 한다 (이미 `lifecycleState` 로 보호).
- `destroy()` 안에서 `handle.close()` 호출 금지. handle 종료는 `ChannelManager` 의 책임. destroy 는 '위에 쌓인 것' (sessions, subscriptions, data channels) 만 정리.

**After 핵심**
```swift
func handleStreamClose() async { await destroy() }
func handleError(error: any Error) async { await destroy() }
```

**안티패턴**
- `destroy()` 안에서 `try? await handle.close()` — `ChannelManager` 호출과 중복.
- destroy 를 단일 호출 가정 — 실제로는 두 경로가 모두 호출될 수 있으므로 반드시 멱등.

---

## 4. Sendable 적합화 가이드라인 (요약)

- `@unchecked Sendable`: **금지**.
- `nonisolated(unsafe)`: Rule I 의 두 패턴에 한해 허용, 반드시 주석으로 근거 명시.
- 그 외 가변 상태는 `actor` 격리 또는 `ManagedAtomic` 같은 원자 자료형 사용.
- 외부 노출 이벤트는 `AsyncStream<T>` + `Continuation` 패턴.
- Subscription / Delegate 류는 가능한 `@MainActor` 전체 격리 또는 actor 격리.

---

## 5. FeatureProvider 마이그레이션 룰

### 5.1. 시그니처 변경

**Before**
```swift
class NoctilucaFeatureProvider: FeatureProvider {
    private weak var clipboardChannel: ClipboardChannel?

    func createChannel(for feature: SiriusFeature,
                       using streamHolder: StreamHolder,
                       identifier: ChannelIdentifier,
                       direction: ChannelDirection,
                       args: [String]) async throws -> ChannelCreationResult { ... }
}
```

**After**
```swift
final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

    func createChannel(for feature: SiriusFeature,
                       handle: ChannelHandle,
                       args: [String]) async throws -> ChannelCreationResult {
        switch feature {
        case .projection:
            return .accepted(ProjectionChannel(handle: handle))
        // ...
        }
    }
}
```

- `streamHolder`/`identifier`/`direction` 인자 제거, `handle: ChannelHandle` 단일 인자.
- 필요하면 `handle.identifier`, `handle.direction`, `handle.feature` 로 읽는다.
- **절대 `handle.activate()` 를 호출하지 말 것.** `ChannelManager` 가 호출한다.

### 5.2. `ChannelCreationResult` 처리

- 기존과 동일. `.accepted(channel)` 또는 `.rejected(code:reason:)`.
- 생성 중 `async` 작업 필요 시 그대로 `try await` 가능 (`createChannel` 이 이미 async throws).

### 5.3. `FeatureProvider` 자체의 Sendable 적합화

현재 `NoctilucaFeatureProvider` 의 `private weak var clipboardChannel: ClipboardChannel?` 는 `FeatureProvider: Sendable` 요구로 인해 v2 에서 컴파일되지 않는다.

**권장안 — State actor**
```swift
final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

    actor State {
        weak var clipboardChannel: ClipboardChannel?
        func setClipboardChannel(_ ch: ClipboardChannel?) { self.clipboardChannel = ch }
        func getClipboardChannel() -> ClipboardChannel? { self.clipboardChannel }
    }
}
```

- 호출부는 `await self.state.setClipboardChannel(channel)`, `await self.state.getClipboardChannel()`.
- `createChannel` 이 이미 async 이므로 await 추가 부담 없음.

**대안 (후속 과제)**
- clipboardChannel 필드 자체 제거 → `TransferChannel.onReady` 클로저에서 `handle.asImpl.session?.channelManager.filter(byFeature: .clipboard).first` 로 매번 조회. State 제거, 오버헤드 존재.

### 5.4. 전체 예시

```swift
final class NoctilucaFeatureProvider: FeatureProvider {
    private let state = State()

    actor State {
        weak var clipboardChannel: ClipboardChannel?
        func setClipboardChannel(_ ch: ClipboardChannel?) { self.clipboardChannel = ch }
        func getClipboardChannel() -> ClipboardChannel? { self.clipboardChannel }
    }

    func supports(_ feature: SiriusFeature) -> Bool { ... }

    func createChannel(for feature: SiriusFeature,
                       handle: ChannelHandle,
                       args: [String]) async throws -> ChannelCreationResult {
        switch feature {
        case .hidio:
            return .accepted(HIDIOChannel(handle: handle))
        case .projection:
            return .accepted(ProjectionChannel(handle: handle))
        case .projectionData:
            return .accepted(ProjectionDataChannel(handle: handle))

        case .transfer:
            let result = try await TransferChannel.createIfAccepts(handle: handle, args: args)

            if case .accepted(let channel as TransferChannel) = result,
               channel.shouldSend() {
                let state = self.state
                switch channel.task {
                case .clipboardData(let itemIdx, let reprIdx):
                    channel.onReady = {
                        Task {
                            let clip = await state.getClipboardChannel()
                            clip?.serveTransferData(channel,
                                                    itemIndex: itemIdx,
                                                    representationIndex: reprIdx)
                        }
                    }
                case .fileTransfer(let name, let path, let offset, let length):
                    if let path {
                        channel.onReady = {
                            Task {
                                let clip = await state.getClipboardChannel()
                                clip?.serveFileTransferData(channel,
                                                            name: name, path: path,
                                                            offset: offset, length: length)
                            }
                        }
                    }
                default: break
                }
            }
            return result

        case .clipboard:
            let channel = ClipboardChannel(handle: handle)
            await state.setClipboardChannel(channel)
            return .accepted(channel)

        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
```

---

### 5.5. 부분 마이그레이션 룰 (`fatalError` 임시 처리)

**상황**: SiriusKit 의 `Channel` / `FeatureProvider` 가 v2 로 옮겨졌지만, NoctilucaServer / NoctilucaClient 의 채널 구현체들은 한 번에 모두 옮겨지지 않는다. HIDIO, Clipboard, Transfer 등은 먼저 마이그레이션하고 나머지(Projection / ProjectionData)는 후속 작업으로 미루는 식이 일반적이다.

이 단계에서 `NoctilucaFeatureProvider` 는 다음과 같은 형태가 된다:

- `createChannel(for:handle:args:)` 시그니처는 **반드시 v2** 를 따른다 (프로토콜 적합성).
- 마이그레이션이 완료된 feature 분기만 `.accepted(FooChannel(handle: handle))` 로 실구현.
- 미마이그레이션 분기는 `fatalError("TODO: \(feature) channel v2 migration pending")` 으로 처리한다.
- v1 시절 원본 로직(예: `clipboardChannel` weak 참조, `TransferChannel.onReady` 클로저 등)은 **`createChannelLegacy(...)` 같은 private helper 메서드로 보존**한다. 이 메서드는 v2 시그니처에서는 호출할 수 없어 컴파일되지 않지만, 후속 PR 에서 동일 로직을 v2 로 이식할 때의 참고 자료로 일부러 남겨 둔다.

**왜 fatalError 인가** — `.rejected(...)` 는 클라이언트 쪽에서 retry 루프를 만들 위험이 있다. fatalError 는 "이 PR 의 빌드는 어차피 broken 이고 HIDIO 외 채널을 열면 안 된다" 는 신호를 강하게 준다. 형아의 합의: "빌드 깨져도 OK".

**왜 legacy helper 인가** — fatalError 한 줄로 분기를 비우면 원본 로직(특히 transfer/clipboard 의 onReady 배선) 이 사라져 후속 PR 마이그레이션에 정보 손실이 생긴다. private helper 로 박제해서 후속 PR 작업자가 그대로 참조할 수 있게 한다.

**주의 사항**
- legacy helper 가 컴파일되지 않는 것은 의도된 broken 상태다. PR description 에 명시.
- HIDIO 외 feature 를 클라이언트가 자동으로 열려고 시도하면 서버가 즉시 crash 한다. smoke test 시 이를 우회해야 한다.
- 후속 PR 에서 해당 feature 를 v2 로 이식할 때 legacy helper 의 로직을 옮긴 뒤 helper 자체는 제거한다.

---

## 6. Session 류 (actor 승격) 룰

### 6.1. 목표

`ProjectionSession`, `AudioProjectionSession` 을 **`actor` 로 승격**한다. 내부 가변 상태(recorder, encoder, isReconfiguring, isStopped, pressureAccumulator, Task handle, Cancellable 등)는 전부 actor-isolated 로 이동. 다음 네 지점에서 경계 넘기 전략을 문서화한다.

1. Delegate 콜백 (캡처 큐)에서 actor 진입 — **핫 패스**
2. Combine sink 에서 actor 진입
3. `deinit` safety-net
4. Delegate 설정 시점의 self 노출 문제

### 6.2. 기본 템플릿

```swift
actor ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")
    private let recorderQueue = DispatchQueue(
        label: "app.noctiluca.server.projection.recorder.video",
        qos: .userInteractive)

    nonisolated let id: UUID
    nonisolated let dataChannel: ProjectionDataChannel

    private let preferredRecorderType: ScreenRecorderType

    private var recorderArgs: ScreenRecorderArgs!
    private var recorder: any ScreenRecorder
    private var encoder: any VideoEncoder
    private var codec: Codec?

    private let frameQueue = FrameQueue<EncodedFrame>(capacity: 8)
    private let frameDropController = FrameDropController()

    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?

    private var qualityPlanner: (any QualityPlanner)?
    private var pressureAccumulator: Float = 0.0
    private var pressureWindowCount: Int = 0
    private let pressureWindowSize: Int = 30

    private var lastSentDegradationNotice: DegradationNotice?
    private var recentEncodingFailure: Bool = false

    private var originalFrameRate: Float = 30.0
    private var currentAppliedFrameRate: Float? = nil

    private var screenLockCancellable: AnyCancellable?
    private var displayChangeCancellable: AnyCancellable?

    private weak var sessionDelegate: ProjectionSessionDelegate?
    private var originalRequest: ProjectionRequest?

    private var targetBitrate = 0
    private var maxBitrate = 0

    private var isReconfiguring = false
    private var isStopped = false

    init(id: UUID,
         dataChannel: ProjectionDataChannel,
         preferredRecorderType: ScreenRecorderType) async {
        self.id = id
        self.dataChannel = dataChannel
        self.preferredRecorderType = preferredRecorderType
        self.recorder = await ScreenRecorderFactory.create(
            preferred: preferredRecorderType, queue: recorderQueue)
        self.encoder = VTVideoEncoder()

        // Combine sink / recorder.delegate = self 는 setup() 로 분리.
    }

    func setup() async {
        screenLockCancellable = await ScreenLockObserver.shared.$isScreenLocked
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.reconfigureRecorder() }
            }

        recorder.delegate = self   // ScreenRecorderDelegate 가 Sendable 이어야 OK (6.6)
    }
}
```

핵심 포인트:
- `id`, `dataChannel` 은 `nonisolated let` 으로 뺀다. actor 바깥에서 hop 없이 접근 가능 + deinit 에서도 안전.
- `init` 이 async 이므로 호출부도 `await` 로 생성.
- `recorder.delegate = self` 는 별도 `setup()` 메서드에서.

### 6.3. Delegate 콜백(캡처 큐) → actor 진입 — 핫 패스

`ScreenRecorderDelegate.didCaptureFrame` 은 `recorderQueue` (DispatchQueue) 에서 호출되며, 여기서 actor-isolated 상태(`frameDropController`, `encoder`) 에 접근해야 한다.

**옵션 1 (채택, 기본)** — `nonisolated` shim + `Task` 진입

```swift
extension ProjectionSession: ScreenRecorderDelegate {
    nonisolated func screenRecorder(_ recorder: any ScreenRecorder,
                                    didCaptureFrame frameData: CMSampleBuffer) {
        Task { [weak self] in
            await self?.handleCapturedFrame(frameData)
        }
    }
}

extension ProjectionSession {
    private func handleCapturedFrame(_ frameData: CMSampleBuffer) {
        let ptsDropResult = frameDropController.shouldDropByPts(frameData)
        if ptsDropResult.shouldDrop { return }
        if ptsDropResult.needsKeyframe { encoder.forceKeyframe() }
        try? encoder.encode(frameID: UInt64(Date().timeIntervalSince1970 * 1000),
                            sampleBuffer: frameData)
    }
}
```

- **장점**: 명쾌, 컴파일러 검사 통과, 적용 기계적.
- **단점**: 프레임당 `Task` 생성 비용 (수 µs). 60fps 기준 초당 60 Task. 측정 후 재평가.
- **핫 패스 순서**: `Task` 는 actor hop 후 scheduling 순서가 역전될 수 있다. `CMSampleBuffer` PTS 를 `FrameDropController` 가 PTS 기반으로 판정하므로 실질적 역전은 무해. 주석에 명시 필수.

**옵션 2 (미채택)** — 중간 serial queue 에서 판정 후 actor hop
- FrameDropController 를 actor 바깥 nonisolated 필드로 유지해야 하므로 Sendable 적합성 재작업 필요. 초기 마이그레이션 권장 X.

**옵션 3 (채택)** — actor custom executor 바인딩
- Swift 5.9+ `unowned ActorExecutor` API 로 actor executor 를 `recorderQueue` 로 고정.
- 캡처 콜백이 이미 해당 queue 에 있으므로 hop 없이 inline 실행.
- 제약: macOS 14+, 구현 복잡도, 다른 actor 호출도 같은 queue 로 재라우팅됨.
- **룰**: **`ProjectionSession` / `AudioProjectionSession` 은 본 마이그레이션에서 옵션 3 을 채택**한다. `nonisolated let recorderQueue: DispatchSerialQueue` 을 actor 에 소유시키고, `nonisolated var unownedExecutor: UnownedSerialExecutor { recorderQueue.asUnownedSerialExecutor() }` 로 바인딩한다. Recorder delegate 콜백은 `assumeIsolated { me in ... }` 로 hop 없이 actor-isolated 메서드를 호출한다. `EventInjector` (Section 10.7.3) 에 이은 두 번째 참조 구현이다.

### 6.4. Combine sink → actor 진입

```swift
self.screenLockCancellable = await ScreenLockObserver.shared.$isScreenLocked
    .receive(on: DispatchQueue.main)
    .removeDuplicates()
    .dropFirst()
    .sink { [weak self] _ in
        Task { [weak self] in await self?.reconfigureRecorder() }
    }
```

- sink 클로저는 actor 외부 → `Task { await self?.something() }` 형태로 경계 넘기.
- **이중 `[weak self]` 주의**: sink 클로저에서 먼저 캡처, 그 안의 `Task` 에서 다시 캡처해야 deinit 이후 dangling reference 방지.

### 6.5. `deinit` safety-net

**문제**
- actor 의 `deinit` 은 nonisolated context → actor-isolated 필드에 직접 접근 불가.
- 기존 v1 deinit 의 `encoderEventLoopTask?.cancel()`, `screenLockCancellable?.cancel()`, `recorder.delegate = nil` 등은 전부 actor-isolated 접근이라 컴파일 에러.

**룰**
- safety-net 의 역할을 축소한다:
  - nonisolated let 필드(`id`, `dataChannel`, `frameQueue` 등)만 사용.
  - recorder/encoder/Task cancel 은 **호출자가 `stop()` 을 반드시 호출한다** 는 전제로 deinit 에서 생략.
  - `ProjectionChannelState.beginDestroy()` 가 이미 `stop()` 을 호출하므로 정상 경로에서는 누수 없음.

```swift
deinit {
    // nonisolated let 만 접근 가능
    let dataChannel = self.dataChannel
    let frameQueue = self.frameQueue

    Task.detached {
        await frameQueue.cancelWaiter()
        try? await dataChannel.close()
    }

    // recorder / encoder / Tasks 는 stop() 이 호출되지 않았다면 누수 가능.
    // 상위 ProjectionChannelState.beginDestroy 가 stop() 을 보장하므로
    // 정상 경로에서는 문제 없음. 주석으로 명시할 것.
}
```

### 6.6. Delegate 설정 시점 (self 노출 문제)

```swift
init(...) async {
    self.recorder = await ScreenRecorderFactory.create(...)
    self.recorder.delegate = self   // ← actor-isolated self 를 non-Sendable delegate slot 에 대입
}
```

- `ScreenRecorderDelegate` 가 non-Sendable 이면 이 대입이 컴파일 에러.

**해법 (채택)**: `ScreenRecorderDelegate` / `AudioRecorderDelegate` / `ProjectionSessionDelegate` 프로토콜에 **`Sendable` 표식 1줄 추가**.

```swift
protocol ScreenRecorderDelegate: AnyObject, Sendable {
    func screenRecorderDidStart(_ recorder: any ScreenRecorder)
    func screenRecorder(_ recorder: any ScreenRecorder, didStopWithError error: (any Error)?)
    func screenRecorder(_ recorder: any ScreenRecorder, didCaptureFrame: CMSampleBuffer)
}
```

- "Recorder/Encoder 프로토콜 본격 리팩터는 범위 밖" 이지만 **`Sendable` 표식 한 줄만은 불가피한 최소 타협**으로 허용.
- 표식 추가 후 구현체 (`ProjectionSession`, `AudioProjectionSession`) 가 actor 이므로 자연스럽게 Sendable.
- delegate 대입은 actor-isolated `setup()` 내부에서 수행하므로 self 를 넘기는 것이 actor 내부 컨텍스트에서 이뤄진다.

### 6.7. 상위 delegate 호출 시 actor 경계 넘기기

```swift
// Before
sessionDelegate?.projectionSession(self, didChangeResolution: updatedCodec)

// After (actor 내부)
if let delegate = sessionDelegate {
    Task { [delegate, self] in
        delegate.projectionSession(self, didChangeResolution: updatedCodec)
    }
}
```

- `ProjectionSessionDelegate` 도 `Sendable` 표식 필요 (`ProjectionChannel` 이 Channel 프로토콜 적합으로 이미 Sendable).
- hop 을 피하고 싶으면 delegate 호출부 전체를 nonisolated 메서드로 뽑아낼 수 있으나, 코드 복잡도 증가.

---

## 7. Subscription 류 룰

**대상**: `CursorEventSubscription`, `DisplayEventSubscription`.

- 단일 `weak var channel: ProjectionChannel?` 을 가진다.
- 기존 `@MainActor func setup()` + `Task.detached` 조합.

**채택 형태**: `final class` + **`@MainActor` 전체 격리**.

```swift
@MainActor
final class CursorEventSubscription {
    nonisolated let id: UUID = UUID()

    private let cursorStateHolder = CursorStateHolder.shared
    private var stateTask: Task<Void, Never>?
    private var hashTask: Task<Void, Never>?

    weak var channel: ProjectionChannel?

    init() {}
    deinit {
        stateTask?.cancel()
        hashTask?.cancel()
    }

    func setup() {
        let cursorStateStream = cursorStateHolder.makeCursorStateStream()
        let cursorHashStream = cursorStateHolder.makeCursorHashStream()
        let initialCursorState = cursorStateHolder.cursorState
        // ... 기존 로직 ...
    }

    nonisolated func destroy() {
        Task { @MainActor [weak self] in
            self?.stateTask?.cancel()
            self?.stateTask = nil
            self?.hashTask?.cancel()
            self?.hashTask = nil
        }
    }
}
```

- `@MainActor` class 전체 격리 → 필드 접근 깔끔.
- `id` 는 `nonisolated let` 으로 뽑아 actor 외부에서 `subscription.id` 접근 가능.
- `destroy()` 는 `nonisolated func` 로 선언하고 내부에서 `Task { @MainActor ... }` 로 main actor 진입. `Task<Void, Never>?.cancel()` 은 스레드 안전.
- `ProjectionChannelState` actor 에서 `cursorSubscription` 을 저장/회수할 때 cross-actor hop 발생, 빈도가 낮아 영향 미미.

`DisplayEventSubscription` 도 동일 패턴. Combine sink 의 `.receive(on: DispatchQueue.main)` 는 유지.

---

## 8. `ChannelEventCompatBridge` 사용 룰

- 채널당 **정확히 1개** 소유. handle 의 `events` `AsyncStream` 은 unicast.
- 필드 선언:
  ```swift
  nonisolated(unsafe) private var channelEventCompatBridge:
      ChannelEventCompatBridge<Self>!
  ```
- `init` 에서 **반드시** 초기화. Optional unwrap 실패는 프로그래머 에러.
- CompatBridge 는 내부에서 `Task.detached` 시작, deinit 에서 자동 cancel.
- CompatBridge 는 `unowned let consumer: Consumer` 로 참조하므로, consumer(=채널) 가 CompatBridge 보다 먼저 해제되면 안 된다. 일반적으로 CompatBridge 가 consumer 의 필드이므로 수명이 자동으로 동기화되어 안전.
- CompatBridge 의 async 메서드 라우팅은 throw 를 swallow 후 TODO 로깅. 채널 내부에서는 가능한 한 throw 를 보존해 향후 로깅 보강 여지 확보.

---

## 9. 마이그레이션 체크리스트

### 9.0. 마이그레이션 진행 상황

- [x] MainChannel (SiriusKit 참조 구현)
- [x] HIDIO (서버/클라이언트)
- [x] Clipboard (서버/클라이언트)
- [x] Transfer (서버/클라이언트)
- [x] **Projection (서버) — 본 PR 에서 완료**
- [ ] Projection (클라이언트)
- [ ] ProjectionData (클라이언트)

### 9.1. 채널 단위
- [ ] `class Foo: Channel` → `final class Foo: Channel, ChannelEventConsumer`
- [ ] `required init(using:...)` → `init(handle:)` 교체
- [ ] `let handle: ChannelHandle` 추가 및 init 에서 대입
- [ ] `override var serviceClass` 제거 → `handleChannelReady()` 에서 `await handle.setServiceClass(_:)`
- [ ] `override handleFrame/handleStreamClose/handleStreamError` 제거 → `ChannelEventConsumer` 4종 구현
- [ ] `sendNonBlocking(...)`, `send(...)` 호출을 `handle.send(...)` 로 교체
- [ ] `super.init / super.handleXxx` 전부 제거
- [ ] CompatBridge 필드 선언/초기화 추가
- [ ] 외부 이벤트 AsyncStream 이 있다면 `nonisolated(unsafe) let events` + `private let continuation` 패턴
- [ ] 가변 필드를 state actor 로 이동 (Combine cancellable 포함)
- [ ] `destroy()` 호출 경로 정리 (`handleStreamClose / handleError → await destroy()`)
- [ ] `@unchecked Sendable` 전부 제거
- [ ] `nonisolated(unsafe)` 각 사용처에 근거 주석
- [ ] 컴파일 및 Swift 6 strict concurrency 경고 0 달성

### 9.2. 세션(Session 류) 단위
- [ ] `class` → `actor`
- [ ] 변경 불가 필드는 `nonisolated let` 으로 노출 (`id`, `dataChannel`, 필요 시 `frameQueue`)
- [ ] delegate 프로토콜(`ScreenRecorderDelegate`, `AudioRecorderDelegate`, `ProjectionSessionDelegate`) 에 `Sendable` 표식 추가
- [ ] delegate 콜백 메서드를 `nonisolated func` 로 선언 + `Task { await self.xxx }` 진입
- [ ] `init` 에서 `recorder.delegate = self` 직접 대입 금지 → `setup()` 으로 분리
- [ ] Combine sink 콜백에서 이중 `[weak self]` 사용 확인
- [ ] `deinit` 에서 actor-isolated 필드 접근 금지 → nonisolated let 만 사용
- [ ] `stop()` 호출을 상위에서 보장 (이미 `ProjectionChannelState.beginDestroy` 가 보장)
- [ ] 상위 `sessionDelegate` 호출 시 `Task` + Sendable 경계 명시

### 9.3. Subscription 단위
- [ ] class 선언에 `@MainActor` 적용
- [ ] `id` 등 불변 식별자를 `nonisolated let` 로 노출
- [ ] `weak var channel: ProjectionChannel?` 의 Sendable 요건 확인 (ProjectionChannel 이 Sendable 이면 OK)
- [ ] `destroy()` 를 `nonisolated func` 로 선언 (Task cancel 전용)

### 9.4. FeatureProvider 단위
- [ ] `createChannel(for:handle:args:)` 시그니처로 교체
- [ ] 각 feature 분기에서 `ChannelType(handle: handle)` 로 생성
- [ ] `weak var clipboardChannel` 등 가변 약 참조는 State actor 로 격리
- [ ] `FeatureProvider` 가 `final class` + `Sendable` 요건 만족
- [ ] `handle.activate()` 를 provider 에서 호출하지 않음 확인

---

## 9.5. 서버 Projection 마이그레이션 — 학습 노트 (실제 구현 중 발견)

본 섹션은 2026-04-11 서버 Projection 마이그레이션 PR 작업 중 발견된, **사전에 문서에 기록되지 않았던 실제 이슈와 해결책**을 기록한다. 후속 작업 (클라이언트 Projection, 기타 미디어 파이프라인) 시 참조용.

### 9.5.1. `ProjectionDataChannel` delegate 는 state actor 격리로 (옵션 A 구현)

계획 문서에서 두 가지 후보(actor 격리 vs `nonisolated(unsafe)` 예외 패턴 3) 중 **actor 격리를 채택**했다. 이유:

- 서버 측 delegate 는 "init 직후 1회 대입" 패턴이 아니다. `ProjectionChannel.handleProjectionRequest`, `handleAudioProjectionRequest` 성공/실패 경로 및 `cleanupTerminationTargets` 등 **여러 곳에서 `setDelegate(nil)` 이 호출**된다.
- Rule I 예외 패턴 3 ("init 직후 1회 설정되는 콜백") 에 엄밀히 부합하지 않는다.
- actor 격리가 약간의 hop 비용이 있지만 delegate 갱신은 매 프레임 경로가 아닌 세션 수준 이벤트에서만 발생하므로 실질 영향 없음.

구현 형태 (**`ProjectionDataChannel.swift` 참조**):

```swift
actor ProjectionDataChannelState {
    private weak var delegate: ProjectionDataChannelDelegate?

    func setDelegate(_ delegate: ProjectionDataChannelDelegate?) { self.delegate = delegate }
    func getDelegate() -> ProjectionDataChannelDelegate? { self.delegate }
}

final class ProjectionDataChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    let state = ProjectionDataChannelState()
    // ...

    func handleError(error: any Error) async {
        let delegate = await state.getDelegate()
        delegate?.projectionDataChannel(self, didEncounterError: error)
    }
}
```

호출부(`ProjectionChannel`, `ProjectionSession`) 는 delegate 에 접근할 때 **항상 `await channel.state.setDelegate(...)` / `await channel.state.getDelegate()` 패턴**을 사용한다.

### 9.5.2. Recorder / Encoder 본체 프로토콜에도 `Sendable` 이 필요하다

처음에는 "actor 내부 stored property 로만 저장하면 타입 자체의 Sendable 은 불필요" 라고 판단했으나, 실제로는 `ProjectionSession` actor 의 `async init` 안에서:

```swift
self.recorder = await ScreenRecorderFactory.create(...)
```

와 같이 **cross-actor boundary 로 non-Sendable 값을 전달**하게 된다 (`ScreenRecorderFactory.create` 는 `@MainActor` isolated). Swift 6 strict concurrency 는 이 반환값이 Sendable 이어야 actor 내부로 들여올 수 있다고 요구한다.

따라서 다음 네 프로토콜에 모두 `Sendable` 표식이 필요하다:

- `ScreenRecorder: AnyObject, Identifiable, Sendable`
- `AudioRecorder: AnyObject, Identifiable, Sendable`
- `VideoEncoder: AnyObject, Sendable`
- `AudioEncoder: AnyObject, Sendable`

그리고 구현체들은 Rule G 확장 예외(미디어 파이프라인 class) 를 적용해 `final class ... @unchecked Sendable` 로 선언한다. 본 PR 에서 교체된 구현체 목록:

- `ScreenCaptureKitScreenRecorder`, `AVFoundationScreenRecorder`
- `ScreenCaptureKitAudioRecorder`
- `VTVideoEncoder`, `ZRLEVideoEncoder`, `MJPGVideoEncoder`, `WebPVideoEncoder`
- `OpusAudioEncoder`, `PCMAudioEncoder`

각 구현체 class 선언 위에는 **근거 주석을 필수**로 붙인다.

### 9.5.3. Recorder 프로토콜의 `queue` 요구사항은 `get` 으로 축소

v1 의 `var queue: DispatchQueue { get set }` 에서 setter 는 실사용이 없었다. Sendable 적합화를 위해 `var queue: DispatchQueue { get }` 으로 축소했다. 구현체는 기존대로 `init(queue:)` 로 주입받아 `let` 또는 `var` 로 저장한다.

### 9.5.4. `ProjectionChannelState.displayChangesCancellable` 는 actor 내부 필드로 흡수

계획 문서 Rule J 에서는 `installDisplayDisconnectSink(_ callback:)` 메서드를 만들어 Combine cancellable 을 actor 내부로 이동하는 형태를 제안했다. 본 PR 에서는 **정확히 그 형태로 구현**했다:

```swift
actor ProjectionChannelState {
    private var displayChangesCancellable: AnyCancellable?

    func installDisplayDisconnectSink(
        _ callback: @escaping @Sendable (CGDirectDisplayID) -> Void
    ) {
        self.displayChangesCancellable = DisplayLayoutManager.shared.displayChangeSubject
            .filter { $0.eventType.contains(.disconnected) }
            .sink { event in
                callback(event.displayID)
            }
    }
}
```

`ProjectionChannel.init` 에서는 `Task { [state] in await state.installDisplayDisconnectSink { ... } }` 로 한 번 호출하고, `completeDestroy()` 에서 `cancellable?.cancel()` 로 해제한다.

### 9.5.5. `@MainActor` Subscription 의 `setChannel` 메서드

`CursorEventSubscription` / `DisplayEventSubscription` 을 `@MainActor final class` 로 격리하면, 외부에서 `subscription.channel = self` 같은 직접 대입이 non-MainActor 컨텍스트에서 불가능해진다. 다음 형태로 전환한다:

```swift
@MainActor
final class CursorEventSubscription {
    weak var channel: ProjectionChannel? = nil
    func setChannel(_ channel: ProjectionChannel?) { self.channel = channel }
}
```

호출부는 `await subscription.setChannel(self)` 형태가 된다. `destroy()` 는 `nonisolated func destroy()` 로 선언하여 호출부가 await 없이 사용할 수 있게 한다 (내부에서 `Task { @MainActor ... }` 로 진입).

### 9.5.6. `AutoQualityPlanner.onQualityAdjustment` 콜백은 Task 로 래핑

`qualityPlanner?.onQualityAdjustment = { [weak self] event in ... }` 할당은 actor-isolated `prepare()` 안에서 일어나지만, planner 자체는 class 이고 콜백은 임의의 스레드에서 발화될 수 있다. actor-isolated `handleQualityAdjustment(_:planner:)` 를 호출하려면 반드시 `Task { [weak self] in await self?.handleQualityAdjustment(event, planner: autoPlanner) }` 로 진입한다.

### 9.5.7. `deinit` 에서 logger 접근 불가 — 경고 로그 생략

`ProjectionSession` / `AudioProjectionSession` 의 `deinit` 은 nonisolated 이므로 actor-isolated `logger` 접근이 불가능하다. v1 에서 "stop() 미호출 경고 로그" 를 남기던 코드는 제거했고, 대신 `nonisolated let dataChannel` 과 `nonisolated let frameQueue` 만 사용해 safety-net 을 수행한다 (문서 Section 6.5 그대로).

`stop()` 미호출 시의 관측 가능성 손실은 후속 과제 — OSLog 기반 nonisolated logger 채널 또는 `ManagedAtomic<Bool> stopCalled` 플래그로 대체 가능.

---

## 10. 케이스 스터디: Projection 채널

### 10.1. `ProjectionChannel`

**핵심 변화**
1. 선언: `class` → `final class ..., ChannelEventConsumer`
2. init 시그니처: `init(handle:)`
3. `override var serviceClass` 제거 → `handleChannelReady()` 에서 호출
4. `displayChangesCancellable` → `ProjectionChannelState` 내부로 이동
5. `handleFrame/handleStreamClose/handleStreamError` → ChannelEventConsumer 구현
6. `sendCursorPositionEvent` 등 편의 메서드 내부를 `handle.send(...)` 로 교체
7. `destroy()` 본체 로직 유지, 호출 경로만 단순화

**After (발췌)**
```swift
final class ProjectionChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .userInput

    private let cursorStateHolder = CursorStateHolder.shared
    let state = ProjectionChannelState()

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음.
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        assert(handle.direction == .remote,
               "ProjectionChannel must be opened from remote side")

        Task { [state] in
            await state.installDisplayDisconnectSink { [weak self] displayID in
                await self?.handleDisplayDisconnected(displayID: displayID)
            }
        }

        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else { throw ChannelError.invalidFrame }
        switch frame.opcode { ... }
    }

    func handleError(error: any Error) async { await destroy() }
    func handleStreamClose() async { await destroy() }
}
```

- `sendCursorPositionEvent` 등:
  ```swift
  func sendCursorPositionEvent(_ state: CursorState) async throws {
      handle.send(nonblocking: .cursorEvent,
                  message: CursorEvent(event: .moveEvent(
                      CursorMoveEvent(displayID: state.belongsTo,
                                      position: SRPoint(x: state.relativePosition.x,
                                                        y: state.relativePosition.y)))))
  }
  ```
- 기존 `try await send(opcode:, message:)` 호출은 기계적으로 `try await handle.send(opcode:, message:)` 로 치환.

### 10.2. `ProjectionDataChannel`

현재 구조: `override var serviceClass { .realtimeVideo }`, `override handleFrame` (no-op), `handleStreamClose/Error` 에서 delegate 호출, `sendNonBlocking(frame:)` 로 프레임 전송.

**After (핵심 부분)**
```swift
final class ProjectionDataChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle
    private static let defaultServiceClass: ServiceClass = .realtimeVideo

    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionDataChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        // 서버 사이드는 송신 전용 → 수신 무시
    }

    func handleError(error: any Error) async {
        await notifyDelegate(error: error)
    }
    func handleStreamClose() async {
        await notifyDelegate(error: nil)
    }

    func send(videoFrame frame: EncodedFrame) {
        let siriusFrame = Self.buildSiriusFrame(videoFrame: frame)
        handle.send(nonblocking: siriusFrame)
    }
    // send(audioFrame:), send(parameterSetMessage:), send(degradationNotice:) 동일 패턴
}
```

**`projectionDelegate` Sendable 처리**

현재의 `weak var projectionDelegate: ProjectionDataChannelDelegate?` 가변 필드는 `Channel: Sendable` 요구로 v2 에서 그대로 컴파일되지 않는다. 두 옵션:

- **옵션 A** — delegate 프로토콜에 `Sendable` 표식 + weak 필드를 `ProjectionChannelState` actor 에 격리하거나 delegate holder 로 감쌈. 현재 구조에 가장 가까움.
- **옵션 B (권장, 후속)** — delegate → `AsyncStream<Event>` 전환.
  ```swift
  enum Event: Sendable {
      case closed
      case errored(any Error)
  }
  nonisolated(unsafe) let events: AsyncStream<Event>
  private let continuation: AsyncStream<Event>.Continuation
  ```
  - ProjectionChannel 이 `for await event in dataChannel.events { ... }` 를 별도 Task 로 구독.
  - `weak var` 가변 상태 자체 제거.
  - Channel v2 의 AsyncStream 중심 설계와 일치.

**이번 마이그레이션 초기 권장**: 옵션 A (최소 변경). 옵션 B 는 Section 11 의 후속 과제로 기록.

### 10.3. `ProjectionSession` (핵심 부분)

**선언 변경**
```swift
// Before
class ProjectionSession: Identifiable { ... }

// After
actor ProjectionSession: Identifiable {
    nonisolated let id: UUID
    nonisolated let dataChannel: ProjectionDataChannel
    // ... 6.2 템플릿 참조
}
```

**init 변경**
- 기존 async init 유지. `self.recorder.delegate = self` 만 `setup()` 으로 분리.
- Combine sink 설치도 `setup()` 으로.

**delegate 콜백**
```swift
extension ProjectionSession: ScreenRecorderDelegate {
    nonisolated func screenRecorderDidStart(_ recorder: any ScreenRecorder) {
        Task { [weak self] in await self?.onRecorderDidStart() }
    }
    nonisolated func screenRecorder(_ recorder: any ScreenRecorder,
                                    didStopWithError error: (any Error)?) {
        Task { [weak self] in await self?.onRecorderDidStop(error: error) }
    }
    nonisolated func screenRecorder(_ recorder: any ScreenRecorder,
                                    didCaptureFrame frameData: CMSampleBuffer) {
        Task { [weak self] in await self?.handleCapturedFrame(frameData) }
    }
}

extension ProjectionSession {
    func onRecorderDidStart() {
        logger.info("Screen recorder started for projection session \(self.id)")
    }
    func onRecorderDidStop(error: (any Error)?) {
        logger.info("Screen recorder stopped, error: \(String(describing: error))")
        if error != nil, !isStopped {
            Task { await self.reconfigureRecorder() }
        }
    }
    func handleCapturedFrame(_ frameData: CMSampleBuffer) {
        let ptsDropResult = frameDropController.shouldDropByPts(frameData)
        if ptsDropResult.shouldDrop { return }
        if ptsDropResult.needsKeyframe { encoder.forceKeyframe() }
        try? encoder.encode(frameID: UInt64(Date().timeIntervalSince1970 * 1000),
                            sampleBuffer: frameData)
    }
}
```

> 주의: `handleCapturedFrame` 은 hot path. 초기에는 옵션 1 유지, 성능 프로파일링 후 옵션 3(custom executor) 전환 여부 결정.

**deinit**: 6.5 규칙에 따라 `nonisolated let` 만 사용. `dataChannel.close()`, `frameQueue.cancelWaiter()` 수준으로 축소.

### 10.4. `AudioProjectionSession`

- 구조가 `ProjectionSession` 보다 단순. 동일 패턴으로 actor 승격.
- `recorder.delegate = self` 는 `setup()` 으로.
- `didCaptureFrame` 에서 `try encoder?.encode(...)` 호출도 `handleCapturedAudioFrame` private 메서드로 감싸고 Task 진입.
- 체크리스트 9.2 그대로 적용.

### 10.5. `CursorEventSubscription` / `DisplayEventSubscription`

Section 7 참조. `@MainActor` 전체 격리.

### 10.6. `NoctilucaFeatureProvider`

Section 5 참조. 시그니처 교체 + State actor.

### 10.7. HIDIO 케이스 스터디

#### 10.7.1. 서버 `HIDIOChannel`

- v1 의 `class HIDIOChannel: Channel` + `override` 4종 + `required init(using:identifier:direction:)` 을 v2 템플릿(Section 4 / Section 10 일반 패턴)으로 교체.
- `serviceClass` 는 `handleChannelReady()` 에서 `await handle.setServiceClass(.userInput)` 로 이관 (Rule F).
- `var keyboardHacks` 가변 배열을 `HIDIOChannelState` actor 로 분리 (Rule G).
- `eventInjector.prepare()` 가 actor 승격으로 `async throws` 가 됨 → init 에서 `Task { try? await injector.prepare() }` 로 기동.
- `handleStreamClose() async` / `handleError(error:) async` 안에서 `await eventInjector.resetKeyboardState()` 호출. v1 시절의 "동기 훅에서 비동기 정리 작업을 어떻게든 기동" 문제는 자연스럽게 사라진다.

#### 10.7.2. `HIDIOChannelState` actor 의 등장

HIDIO 서버 채널은 **수신 전용**이고 `ChannelEventCompatBridge` 의 단일 `Task.detached` 에서만 `handleFrame` 이 순차 호출된다. 따라서 이론상 별도 격리가 없어도 동시 접근은 발생하지 않는다. 그럼에도 `HIDIOChannelState` actor 를 도입하는 이유는:

1. 채널 본체가 `final class : Sendable` 이 되어야 하는데, `var keyboardHacks: [KeyboardHackPluginV1]` 같은 가변 배열을 본체에 두면 Sendable 적합화가 깨진다.
2. `HIDIOKeyboardHackRegistry.shared` 가 actor 로 승격되어 `await snapshot()` 호출이 필요해지므로, 이 호출을 호스팅할 async 컨텍스트가 필요하다. state actor 가 그 자리를 제공한다.
3. 향후 HIDIO 채널 본체가 더 많은 가변 상태를 갖게 되더라도 동일 actor 안에 격리할 수 있도록 자리를 미리 확보한다.

#### 10.7.3. `EventInjector` actor 승격 + custom executor

서버의 `EventInjector` 는 v1 시절부터 내부적으로 `serialQueue: DispatchQueue` + `enqueue { ... }` 로 모든 가변 상태를 직렬화하고 있었다. v2 마이그레이션에서는 다음 두 단계를 거친다.

**단계 1**: `class` → `actor` 승격. 모든 가변 필드는 자연스럽게 actor-isolated 가 된다. `enqueue { [weak self] in self?.fooOnQueue() }` 패턴은 전부 제거되고, `func foo()` 본문이 actor-isolated 메서드로 옮겨진다.

**단계 2**: actor 의 unowned executor 를 기존 `serialQueue` 에 바인딩한다.

```swift
actor EventInjector {
    nonisolated let serialQueue: DispatchSerialQueue =
        DispatchSerialQueue(label: "EventInjector", qos: .userInteractive)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        serialQueue.asUnownedSerialExecutor()
    }
    // ...
}
```

이 두 줄로 인해 `EventInjector` 의 모든 actor-isolated 호출은 **별도의 actor hop 없이 기존 serial queue 위에서 직접 실행**된다. v1 의 `serialQueue.async { ... }` semantic 이 그대로 유지되며, 호출자 입장에서는 `await eventInjector.postKeyDown(keycode)` 한 줄로 안전하게 호출할 수 있다.

요구사항: macOS 14+ / iOS 17+ (`DispatchSerialQueue.asUnownedSerialExecutor()`). NoctilucaServer 앱 deployment target 이 macOS 15.0 이라 사용 가능.

`DispatchSourceTimer.setEventHandler` 는 같은 serialQueue 위에서 호출되므로, 콜백 안에서는 `Actor.assumeIsolated(_:)` 로 actor-isolated 메서드를 hop 없이 직접 호출할 수 있다 (Swift 5.9+ 표준 API):

```swift
timer.setEventHandler { [weak self] in
    guard let self else { return }
    self.assumeIsolated { me in
        me.handleRepeatTick()
    }
}
```

**참고**: actor + custom executor 패턴은 "lock 도 actor hop 도 원치 않는, 이미 직렬화가 보장된 외부 자원을 actor 의 격리 보장 안으로 끌어들이는 가장 클린한 기법" 이다. Recorder/Encoder 처럼 콜백 큐가 명확히 있는 객체에 적용할 가치가 있다.

#### 10.7.4. `HIDIOKeyboardHackRegistry` actor 정식 승격

기존 `class HIDIOKeyboardHackRegistry { static let shared; private(set) var hacks: [String: KeyboardHackPluginV1] = [:] }` 는 lock 도 없이 가변 dict 를 노출하는 구조였다. v2 에서는 다음과 같이 정식 actor 로 승격한다.

```swift
actor HIDIOKeyboardHackRegistry {
    static let shared = HIDIOKeyboardHackRegistry()

    private var hacks: [String: KeyboardHackPluginV1] = [:]

    func register(_ plugin: KeyboardHackPluginV1) { ... }
    func snapshot() -> [String: KeyboardHackPluginV1] { hacks }
}
```

- `register(_:)` 호출부(`PluginBundleRegistry.swift`) 는 이미 async 이므로 `await` 한 줄만 추가하면 된다.
- `snapshot()` 은 `HIDIOChannelState.updateHacks(from:)` 안에서 호출되며, 반환값은 dict 값 복사이므로 actor 경계를 안전하게 넘긴다.
- `KeyboardHackPluginV1` 프로토콜에 `Sendable` 요구사항을 추가해야 dict 값이 actor 경계를 넘을 수 있다. 동시에 `KeyboardHackResult` 와 `SoftwareLicense` 도 `Sendable` 표식이 필요하다 (NoctilucaPluginKit 측 한 줄 수정).

#### 10.7.5. 클라이언트 `HIDIOChannel` / `HIDIOController`

클라이언트 측은 다음과 같이 옮긴다.

- `HIDIOChannel` 은 서버와 동일한 v2 템플릿을 따른다. `direction == .local` assertion, 수신 no-op (`handleFrame` 비움), `handleStreamClose/handleError` 에서 `await MainActor.run { controller.shutdown() }`.
- `HIDIOController` 는 **`@MainActor final class`** 로 격리한다. 입력 소스(NSEvent monitor / GCKeyboard / GCMouse / UIKit responder / CGEventTap) 의 대부분이 이미 main thread 컨텍스트에서 발생하므로, MainActor 격리가 가장 hop 이 적다. actor 승격은 오히려 main → global → main 의 2회 hop 을 만든다.
- `HIDIOController` 는 `unowned channel: HIDIOChannel` 대신 `private let handle: ChannelHandle` 을 직접 보유한다. `channel.sendNonBlocking(opcode:message:)` 호출은 `handle.send(nonblocking: .hidioPacket, message: ...)` 로 교체. `handle.send(nonblocking:)` 은 atomic fast-path 로 lock-free enqueue 만 수행하므로 main thread 블로킹이 발생하지 않는다.
- `HIDIOController.init(handle:)` 은 `nonisolated init` 으로 선언한다. `NoctilucaFeatureProvider.createChannel(for:handle:args:)` 가 MainActor 컨텍스트가 아니므로, 동기적으로 controller 를 만들기 위해 init 자체는 nonisolated 가 필요하다. 내부 publisher Task 는 기존대로 `Task { [weak self] in await self?.publisherTaskMain() }` — MainActor inheritance 로 자연스럽게 main thread 에서 실행된다.
- `deinit` 은 nonisolated context. MainActor-isolated 메서드는 직접 호출할 수 없으므로 `eventStreamContinuation.finish()` 와 `publisherTask?.cancel()` 같은 Sendable 호출만 수행한다.

#### 10.7.6. 입력 디바이스의 `@MainActor` 격리 + CGEventTap 특례

`HIDIOVirtualDevice` 프로토콜의 `connect(to:)` / `disconnect()` 요구사항에는 **메서드 단위 `@MainActor`** 를 부착한다. 프로토콜 전체에 `@MainActor` 를 거는 것보다 더 유연하며, 구현체별로 클래스 자체를 MainActor 로 격리할지 일부 메서드만 격리할지 선택할 수 있게 한다.

- **`HIDIOAppKitMouse` / `HIDIOGCKeyboard` / `HIDIOGCMouse` / `HIDIOUIKitKeyboard` / `HIDIOUIKitMouse`**: 클래스 자체에 `@MainActor` 를 부착한다. NSEvent / UIKit / GameController 콜백이 모두 main 컨텍스트(또는 main 보장이 약한) 이므로 MainActor 격리가 자연스럽다. NotificationCenter sink 와 valueChangedHandler 클로저 안에서는 `Task { @MainActor [weak self] in ... }` 으로 명시적 진입한다.
- **`HIDIOCocoaEventTapKeyboard`** (macOS 전용): CGEventTap 콜백이 **CGEventTap 전용 run loop thread** 에서 호출되므로 클래스 통째 MainActor 격리는 불가능하다. 대안으로 다음 패턴을 쓴다.
  1. 프로토콜 요구사항(`connect`/`disconnect`) 만 `@MainActor` 로 구현.
  2. `weak var controller: HIDIOController?` 필드는 `nonisolated(unsafe) weak var` 로 두고, 쓰기 시점(`connect`/`disconnect` MainActor)과 읽기 시점(eventTap thread) 모두 명확히 분리한다. `disconnect` 가 `stopEventTap()` 을 먼저 호출해 콜백을 차단하므로 실질적인 race 는 없다 — Rule I 예외 패턴 3 으로 문서화 (아래 Section 13.3).
  3. `dispatchKeyEvent(_:)` 는 eventTap thread 에서 호출된다. controller 의 MainActor-isolated 메서드(`keyDown`/`keyUp`) 를 호출하기 위해 `Task { @MainActor [weak target] in target?.keyDown(...) }` 으로 진입한다. 핫 패스이므로 후속에서 프로파일링 후 custom executor 등 최적화 검토.
  4. nonisolated `deinit` 에서는 `stopEventTap()` 호출만 수행한다 (CGEvent API 는 thread-safe). `disconnect()` 자체는 MainActor 메서드라 deinit 에서 직접 부를 수 없다.

---

## 11. 남은 기술 부채 / 앞으로 할 일

- **`ChannelEventCompatBridge` 걷어내기**
  - 최종 목표는 각 채널이 `Task { for await event in handle.events { ... } }` 를 직접 돌려 이벤트를 소비하는 것.
  - `ChannelEventConsumer` 프로토콜의 존속 여부도 함께 재검토.
  - 서버 앱 v2 마이그레이션이 끝난 뒤 별도 PR.
- **`ScreenRecorderDelegate` / `AudioRecorderDelegate` 본격 Sendable 적합화**
  - 이번에는 `Sendable` 표식 한 줄만 추가. 프로토콜 요청/응답 시그니처나 데이터 경로는 그대로.
  - 후속: delegate → `AsyncStream<CapturedFrame>` 전환 검토.
- **`FrameDropController` 동시성 정식화**
  - 현재는 `ProjectionSession` actor 내부 필드로 격납. 내부 상태가 실제로 actor-isolated 경로만 사용하는지 감사 필요.
  - 장기적으로 struct + inout API 또는 dedicated actor.
- **actor custom executor (6.3 옵션 3)** — **채택 완료**
  - `ProjectionSession` / `AudioProjectionSession` 양쪽에 `DispatchSerialQueue.asUnownedSerialExecutor()` 적용.
  - 후속 과제: 실제 recorder delegate 가 `assumeIsolated` 호출 시 trap 없이 통과하는지 실기기 검증.
- **`ProjectionDataChannel` → stream 기반 이벤트 (10.2 옵션 B)**
  - 현재는 옵션 A (`ProjectionDataChannelState` actor 로 delegate 격리) 로 구현되어 있다. 후속 PR 에서 `AsyncStream<Event>` 로 전환해 `weak var delegate` 자체를 제거한다.
- **`FeatureProvider` 의 `clipboardChannel` 약 참조 제거**
  - `channelManager.filter(byFeature: .clipboard)` 로 대체. State actor 자체 제거.
- **`ChannelEventCompatBridge` 의 `handleFrame` throw swallow 로깅 보강**
  - 현재 TODO 주석. SiriusKit 측에 로깅 훅 추가 필요.
- **문서 승격**
  - projection 채널 마이그레이션이 끝나면 `MIGRATION_RULES.md` 를 `NoctilucaServer/docs/channel-v2-migration.md` 로 승격(rename + git history 보존).
- **Projection 외 feature 분기 fatalError 제거 완료**
  - 서버/클라이언트 양쪽 `NoctilucaFeatureProvider` 의 `.transfer`, `.clipboard`, `.hidio` 분기는 마이그레이션이 완료되었다. 현재 `.projection`, `.projectionData` 에 남아 있는 fatalError 는 후속 작업에서 해결한다.
- **HIDIO 전용 테스트 추가 (서버/클라이언트)**
  - 서버: `HIDIOChannel.handleFrame` → `EventInjector` 로 이어지는 경로의 통합 테스트. `MockStream` 패턴 차용 가능.
  - 클라이언트: `HIDIOController` 의 송신 파이프라인(`yield` → `publisherTaskMain` → `handle.send(nonblocking:)`) 검증.
- **`HIDIOCocoaEventTapKeyboard` 의 핫패스 hop 프로파일링**
  - 현재 `dispatchKeyEvent(_:)` 가 키 이벤트마다 `Task { @MainActor in ... }` 를 만든다. 실측해서 비용이 유의미하면 actor custom executor 또는 lock-free queue 로 hop 우회 검토.
- **`EventInjector.DispatchSourceTimer + assumeIsolated` 패턴 스트레스 테스트**
  - 키 리피트 발사 중 `assumeIsolated` 가 dynamic check 를 안정적으로 통과하는지 확인. 실패 시 fallback 으로 Task hop 으로 회귀.
- **`KeyboardHackPluginV1` 구현체들의 본격 Sendable 적합화**
  - 이번에는 프로토콜에 `Sendable` 표식만 추가. `CJKEmulateWin32HangulToggleHack` 같은 구현체는 `NSWindow` 가변 필드 등으로 인해 실제 적합성이 깨져 있다 — 후속 PR 에서 `@MainActor final class` 등의 적합화 필요.

---

## 12. 검증 방법

### 12.1. 컴파일

```bash
xcodebuild -workspace NoctilucaServer.xcworkspace \
           -scheme NoctilucaServer \
           -configuration Debug build

xcodebuild -workspace NoctilucaServer.xcworkspace \
           -scheme NoctilucaClient \
           -configuration Debug build
```

- Swift 6 strict concurrency 가 켜진 상태에서 **경고 0** 목표.
- strict 설정 확인:
  ```bash
  xcodebuild -showBuildSettings -workspace NoctilucaServer.xcworkspace \
             -scheme NoctilucaServer | grep -i strict
  ```

### 12.2. 테스트

```bash
xcodebuild -workspace NoctilucaServer.xcworkspace \
           -scheme NoctilucaServerTests \
           -configuration Debug test

xcodebuild -workspace NoctilucaServer.xcworkspace \
           -scheme NoctilucaServerTests \
           -only-testing:NoctilucaServerTests/AutoQualityPlannerTests test
```

### 12.3. 실행 시나리오

1. 서버 실행 → 클라이언트 접속 → 메인 채널 핸드셰이크/인증 완료.
2. `ProjectionRequest` 로 비디오 세션 시작 → `ProjectionSessionCreatedEvent` 수신 확인 → 영상 수신 정상.
3. `StopProjectionRequest` 로 정상 종료 → `ProjectionSessionEndedEvent` 수신.
4. 클라이언트 연결 강제 종료 → 서버 로그에서 `destroy()` → `ProjectionSession.stop()` 호출 순서 확인.
5. 디스플레이 분리 → `displayDisconnected` 이벤트 → `ProjectionSessionEndedEvent(reason: .displayDisconnected)` 발송.
6. `AudioProjectionRequest` → 사운드 수신 확인.
7. `SubscribeCursorEventsRequest` → 120Hz 스로틀 커서 이벤트 수신.
8. `SubscribeDisplayChangesRequest` → 모니터 토글 시 이벤트 수신.
9. 60fps 장시간 스트리밍 → Instruments Leaks 로 누수 확인.

### 12.4. Concurrency 런타임 검증

- Instruments **Swift Concurrency** 템플릿:
  - `handleCapturedFrame` Task 생성 오버헤드 측정.
  - actor hop 통계.
- 임계값: 60fps 기준 `handleCapturedFrame` hop 비용이 프레임당 0.5ms 초과 시 6.3 옵션 3 전환 고려.

## 열린 질문 (이 문서에 반영되지 않은, 추후 결정해도 되는 것들)

- **`ProjectionDataChannel` delegate → AsyncStream 전환** (10.2 옵션 B) — 초기 마이그레이션에서는 옵션 A 로 최소 변경, 후속으로 옵션 B 적용.
- **actor custom executor** (6.3 옵션 3) — 프로파일링 이후 결정.
- **`FeatureProvider` State actor vs 완전 제거** — 초기 State actor, 후속으로 제거 검토.

---

## 13. 클라이언트 앱 마이그레이션 룰

이 섹션은 **클라이언트 앱 (NoctilucaClient, macOS / iOS 공용)** 의 채널 v2 마이그레이션 룰을 정리한다. 서버 룰과 공통되는 부분은 Section 3~10 을 그대로 따르고, 여기에는 클라이언트 고유의 차이점만 기록한다.

### 13.1. 서버 룰과의 차이

| 항목 | 서버 | 클라이언트 |
|---|---|---|
| 채널 direction | `.remote` (수락 측) | `.local` (오픈 측) |
| 채널 본체 (e.g. HIDIO) | 수신 처리 메인 | 수신은 보통 no-op, 송신 파이프라인이 핵심 |
| FeatureProvider | 서버 측 channel manager 가 호출 | 클라이언트 측 channel manager 가 호출 |
| `ClientSession` extension | `Channel.clientSession` 사용 (Rule H) | 해당 사항 없음 |
| Subscription 류 (커서/디스플레이) | 있음 | 없음 |
| 입력 디바이스 격리 | 없음 (서버는 인젝션만) | 핵심 주제 (Section 13.3) |

### 13.2. `@MainActor final class` 컨트롤러 패턴

클라이언트 앱의 송신 파이프라인 컨트롤러(`HIDIOController`)는 다음 형태를 기본으로 한다.

```swift
@MainActor
final class HIDIOController {
    private let handle: ChannelHandle           // ChannelHandle 직접 보유
    private let eventStream: AsyncStream<HIDEvent>
    private let eventStreamContinuation: AsyncStream<HIDEvent>.Continuation
    private var publisherTask: Task<Void, Never>? = nil

    nonisolated init(handle: ChannelHandle) {
        self.handle = handle
        var cont: AsyncStream<HIDEvent>.Continuation!
        self.eventStream = AsyncStream<HIDEvent> { c in cont = c }
        self.eventStreamContinuation = cont

        self.publisherTask = Task { [weak self] in
            await self?.publisherTaskMain()
        }
    }

    private func publisherTaskMain() async {
        // MainActor-inherited Task → main thread 에서 실행.
        // handle.send(nonblocking:) 은 atomic fast-path 라 main 을 블로킹하지 않음.
        for await event in self.eventStream {
            let packet = HIDIOPacket(...)
            handle.send(nonblocking: .hidioPacket, message: consume packet)
        }
    }
}
```

핵심 결정:
- **클래스 자체에 `@MainActor` 부착**. 입력 소스 대부분이 main thread 컨텍스트라 hop 비용이 가장 낮다. 일반 `actor` 승격은 main → global → main 으로 hop 이 두 배 늘어난다.
- **`init(handle:)` 는 `nonisolated init`** 로 선언. FeatureProvider.createChannel 컨텍스트는 main 이 아니므로 동기적으로 controller 를 생성하려면 nonisolated 가 필수.
- **`channel: HIDIOChannel` unowned 참조 대신 `let handle: ChannelHandle`**. 채널과 controller 의 결합도를 낮추고, 송신 API 를 channel 위가 아닌 handle 위에서 호출한다.
- **Sendable 보장이 어려운 가변 필드(`PassthroughSubject`, `KeyEventPipelineChain` 등) 는 MainActor isolated stored property 로 둠**. 외부에서 접근하지 못하도록 캡슐화.
- **`deinit` 은 nonisolated context**. MainActor-isolated 메서드는 직접 호출 불가. `eventStreamContinuation.finish()` / `publisherTask?.cancel()` 같은 Sendable 호출만 수행한다.

### 13.3. 외부 콜백(입력 디바이스) → MainActor 진입 패턴

`HIDIOVirtualDevice` 프로토콜의 `connect(to:)` / `disconnect()` 요구사항에는 **메서드 단위 `@MainActor`** 를 부착한다 (Section 10.7.6 참조).

구현체는 다음 두 패턴 중 하나를 선택한다.

**패턴 A — 클래스 전체 `@MainActor` 격리** (대부분의 디바이스):

```swift
@MainActor
final class HIDIOGCKeyboard: HIDIOVirtualDevice { ... }
```

NSEvent local monitor, UIKit responder, GameController valueChangedHandler 등 콜백 컨텍스트가 main 에 가까운 경우 사용. NotificationCenter sink 클로저나 valueChangedHandler 안에서는 isolation 이 보장되지 않으므로 명시적으로 `Task { @MainActor [weak self] in ... }` 으로 진입한다.

**패턴 B — 메서드 단위 격리 + nonisolated 본체** (CGEventTap 같은 별도 run loop 디바이스):

`HIDIOCocoaEventTapKeyboard` 처럼 콜백이 별도 thread 에서 발생하는 경우 클래스 전체를 MainActor 로 격리할 수 없다.

```swift
final class HIDIOCocoaEventTapKeyboard: HIDIOVirtualDevice, CInteropHandle {
    nonisolated(unsafe) private weak var controller: HIDIOController?
    // ↑ Rule I 예외 패턴 3 (lock 대체로 disconnect 시 stopEventTap 이 콜백 차단)

    @MainActor
    func connect(to controller: HIDIOController) {
        self.controller = controller
        startEventTapIfNeeded()
    }

    @MainActor
    func disconnect() {
        stopEventTap()        // 콜백 차단 먼저
        controller = nil      // 그 다음 참조 해제
    }

    // eventTap 전용 thread 에서 호출
    private func dispatchKeyEvent(_ event: KeyEvent) {
        let target = controller     // nonisolated(unsafe) 읽기
        guard let target else { return }

        Task { @MainActor [weak target] in
            guard let target else { return }
            target.keyDown(keyCode: event.keyCode)
        }
    }

    deinit {
        // nonisolated. disconnect() 를 부를 수 없으므로 thread-safe 한
        // stopEventTap() 만 호출하여 dangling thread 를 막는다.
        stopEventTap()
    }
}
```

### 13.4. `RemoteSession.HIDIO` deinit 패턴

`RemoteSession.HIDIO` 는 `@MainActor final class` 로 격리한다. controller 와 session 이 모두 MainActor-isolated 객체이므로, deinit (nonisolated) 에서는 직접 호출할 수 없고 캡처를 통한 Task 진입이 필요하다.

```swift
deinit {
    let controller = self.controller
    let session: HIDIOSession? = self.session
    Task { @MainActor in
        controller.removeHook(
            for: HIDIOKeystrokeHookIdentifier(rawValue: "...")
        )
        session?.stopSession()
    }
}
```

`controller` 와 `session` 은 `let` 필드 또는 `var` 이지만 nonisolated context 에서 캡처해 strong reference 로 Task 에 넘긴다. self 캡처는 deinit 시점이라 금지.

### 13.5. 클라이언트 FeatureProvider 의 특이점

- `import SiriusKitClient` 를 사용한다 (서버는 `SiriusKit`).
- `progressTracker` / `clipboardChannel` 같은 weak 참조 필드는 v1 시절 전부 보유하던 상태였다. v2 마이그레이션 PR (HIDIO) 에서는 Rule 5.5 에 따라 `createChannelLegacy(...)` private helper 로 보존하고 새 createChannel 에서는 HIDIO 분기만 실구현한다.
- 후속 PR 에서 `Transfer` 채널 v2 화 가 끝나면 `progressTracker` 는 `actor State` 안으로 옮긴다 (Rule 5.3 패턴).

### 13.6. 주변 타입 격리 전략

클라이언트 측 HIDIO 마이그레이션과 함께 다음 타입들도 이번 PR 에서 동시성 정합화한다.

| 타입 | 결정 | 근거 |
|---|---|---|
| `HIDIOKeystrokeHook` | `final class ... Sendable`, `action: @Sendable () -> Void` | 훅 클로저가 Task { @MainActor } 를 감싸 호출되며 actor 경계 cross |
| `KeySequence` | `Sendable` 표식 | stored property 가 모두 Sendable |
| `KeyEventPipelineChain` / `KeyEventRebinder` | `@MainActor final class` | 호출처(`HIDIOController`, `RemoteSession.HIDIO`) 모두 MainActor |
| `SettingsStore` | `@MainActor final class` | 사용처가 대부분 SwiftUI/MainActor 컨텍스트, `static let shared` 의 Sendable 보장 |
| `KeyboardHackPluginV1` (NoctilucaPluginKit) | `protocol ... Sendable` | actor 경계 cross. 구현체 Sendable 적합화는 후속 |
