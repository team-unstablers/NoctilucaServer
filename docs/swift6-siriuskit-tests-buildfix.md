# SiriusKitTests — Swift 6 빌드 블로커 보완 & CodecFourCC 테스트 추가

> **작성일**: 2026-04-12
> **대상 타겟**: `SiriusKit` Swift Package의 `SiriusKitTests`
> **기준 커밋**: `31caeb3` (PR #253 — migrate-to-swift6 머지) 이후 상태
> **트리거**: `SiriusKitCore/channel/msgdef/v1/channels/projection/CodecFourCC.swift`에 대한 유닛 테스트 작성 요청

---

## 1. 배경

### 1.1. 요청
`CodecFourCC.swift`는 FourCC(4-byte 코드)를 `UInt32`로 패킹/언패킹하고 `Codable`을 통해 4자 JSON 문자열로 직/역직렬화하는 값 타입이다. 다음 동작에 대한 유닛 테스트가 필요했다.

- `init(_:_:_:_:)` Character 4개로 big-endian 패킹
- `init(rawValue:)` / `stringRepresentation` 라운드트립
- 정적 상수 (`avc1`, `hvc1`, `vp80`, `zrle`, `mjpg`, `webp`)의 문자열·raw 값 일치
- `Equatable`
- `debugDescription` 포맷 (`"FourCC (AVC1, 0x41564331)"`)
- `Codable` 인코딩/디코딩 라운드트립 및 길이 검증 (4자 아님 → 에러)

### 1.2. 예기치 않은 블로커
처음 `swift test --filter CodecFourCCTests`를 실행했을 때, 새 파일과 무관한 기존 테스트 파일들에서 **Swift 6 strict concurrency 에러가 쏟아지면서 `SiriusKitTests` 타겟 전체의 컴파일이 막히는 상태**였다. `PR #253` Swift 6 마이그레이션 시점에 테스트 타겟 일부가 함께 업데이트되지 못한 것으로 보인다.

`swift test`는 타겟 단위로 컴파일하기 때문에, 이 에러들을 건드리지 않고서는 새로 작성한 테스트조차 실행시킬 수 없었다.

---

## 2. 스코프

### 스코프
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/CodecFourCC.swift`에 대한 유닛 테스트 신규 작성
- `SiriusKitTests` 타겟을 다시 컴파일 가능한 상태로 복구하기 위한 **최소한의** 기존 테스트/목 파일 수정
- 프로덕션 코드(`Sources/`)는 건드리지 않음

### 비-스코프
- `SiriusKitTests` 타겟의 **런타임 정상화**. 빌드 복구 과정에서 `ServerTestHarness.simulateClientConnection()` 경로의 race condition(§5 참조)이 드러났으나, 22곳의 호출처를 async로 전환해야 하고 원래 작업 범위를 초과하므로 이번 PR에서는 다루지 않는다.
- `SiriusKit`(클라이언트 역할)이나 `SiriusKitClientTests` 쪽의 점검.

---

## 3. 신규: `CodecFourCCTests`

**위치**: `SiriusKit/Tests/SiriusKitTests/channel/msgdef/v1/channels/projection/CodecFourCCTests.swift`

Swift Testing(`import Testing`) 기반이며, 같은 디렉토리 규칙(`projection_data/TiledFrameTests.swift`)의 스타일을 따른다. `@Suite("CodecFourCC")` 하위에 15개 `@Test`를 둔다.

### 주요 검증 포인트
- `init(_:_:_:_:)`가 big-endian으로 바이트를 패킹하는지 (`"AVC1"` → `0x41564331`)
- `stringRepresentation`이 원래 ASCII 4자로 복원되는지
- 정적 상수 6종(`avc1`, `hvc1`, `vp80`, `zrle`, `mjpg`, `webp`)이 문서화된 문자열과 정확한 raw 값을 갖는지
- `Equatable`: 동일 raw 값은 같고, 다른 raw 값은 다름
- `debugDescription`: `"FourCC (WEBP, 0x57454250)"` 형식
- `Codable`:
  - 인코딩 결과가 4자 JSON 문자열 (`{"codec":"AVC1"}`)
  - 4자 문자열 디코딩 허용
  - 길이 ≠ 4(빈 문자열, 3자, 5자)는 `DecodingError`로 거부
  - 래퍼 구조체(`Wrapper`)로 감싸 플랫폼별 top-level fragment 지원 차이를 우회

### 결과
```
􀟈  Test run started.
􀟈  Suite "CodecFourCC" started.
...
􁁛  Suite "CodecFourCC" passed after 0.001 seconds.
􁁛  Test run with 15 tests in 1 suite passed after 0.001 seconds.
```
15/15 PASS.

---

## 4. 빌드 블로커 수정 내역

모두 테스트 및 목 파일. 프로덕션 코드는 손대지 않았다.

### 4.1. `Tests/SiriusKitTests/transport/quic/QUICTransportTest.swift`

**증상**
```
error: non-final class 'TestServerDelegate' cannot conform to 'Sendable'; use '@unchecked Sendable'
error: stored property 'didStartListening' of 'Sendable'-conforming class 'TestServerDelegate' is mutable
```
`serverStartsSuccessfully()` 안의 로컬 `class TestServerDelegate`가 `ServerRoleRootTransportDelegate`(`Sendable`)를 채택하지만 `final`이 아니고 mutable 프로퍼티를 갖고 있었다. 같은 파일의 `e2eTestCase_1()`에 선언된 또 다른 `TestServerDelegate`는 이미 `final class ... @unchecked Sendable`로 맞춰져 있는 상태.

**수정**
```diff
- class TestServerDelegate: ServerRoleRootTransportDelegate {
+ final class TestServerDelegate: ServerRoleRootTransportDelegate, @unchecked Sendable {
```

### 4.2. `Tests/SiriusKitTests/server/Mocks/MockSiriusServerDelegate.swift`

**증상**
```
error: stored property 'didStart' of 'Sendable'-conforming class 'MockSiriusServerDelegate' is mutable
```
`SiriusServerDelegate`가 Swift 6 마이그레이션에서 `AnyObject, Sendable`로 바뀌면서, 기록용 mutable 프로퍼티(`didStart`, `didStop`, `lastError`, `acceptedSessions`)를 가진 mock이 Sendable을 만족하지 못함.

**수정**
```diff
- final class MockSiriusServerDelegate: SiriusServerDelegate {
+ final class MockSiriusServerDelegate: SiriusServerDelegate, @unchecked Sendable {
```
테스트 스레드에서만 접근하는 fake이므로 `@unchecked`로 타협.

### 4.3. `Tests/SiriusKitTests/server/Helpers/ServerTestHarness.swift`

**증상**
```
error: actor-isolated property 'delegate' can not be mutated from a nonisolated context
```
`SiriusServer`가 `class` → `public actor SiriusServer`로 바뀌었기 때문에, harness의 sync `init()`에서 `server.delegate = serverDelegate`를 직접 대입할 수 없게 됐다.

**수정 방식**
- `SiriusServer`에 이미 존재하는 async API `public func setDelegate(_:)`(`SiriusServer.swift:38`)를 활용
- `init()`에서 delegate 설정을 제거하고, `startup()` async 메서드 안에서 `await server.setDelegate(serverDelegate)`를 호출
- 기존 테스트 호출 패턴(`let harness = ServerTestHarness(); try await harness.startup()`)은 그대로 유지 — 호출 사이트 변경 0건

```diff
  init() {
      rootTransport = MockServerRoleRootTransport()
      featureProvider = MockFeatureProvider()
      serverDelegate = MockSiriusServerDelegate()
      server = SiriusServer(serverTransport: rootTransport, featureProvider: featureProvider)
-     server.delegate = serverDelegate
  }

  func startup() async throws {
+     await server.setDelegate(serverDelegate)
      try await server.startup()
  }
```

### 4.4. `Tests/SiriusKitTests/server/ServerErrorHandlingTests.swift` / `ClientSessionCreationTests.swift`

**증상**
```
macro expansion #expect:1:xx: error: actor-isolated property 'sessions' cannot be accessed from outside of the actor
```
`SiriusServer.sessions`가 actor-isolated 프로퍼티라 외부에서 직접 읽을 수 없음.

**수정**
두 파일의 `harness.server.sessions` 접근을 모두 `await harness.server.sessions`로 변경 (테스트 함수는 이미 `async throws`).
- `ServerErrorHandlingTests.swift`: 4곳 (L40, L52, L68, L81)
- `ClientSessionCreationTests.swift`: 2곳 (L22, L57)

---

## 5. 남은 이슈 — 런타임 race condition

빌드 블로커는 모두 제거됐고 `CodecFourCCTests`는 통과하지만, 위 4.4에서 수정한 테스트들은 **런타임에 실패**한다.

### 5.1. 증상
```
SiriusKitTests/ServerTestHarness.swift:40: Fatal error:
Unexpectedly found nil while unwrapping an Optional value
```
`serverDelegate.acceptedSessions.last!`가 nil — 즉 `MockServerRoleRootTransport.simulateClientConnection(...)`을 호출한 직후인데도 delegate의 `acceptedSessions`가 비어 있다.

### 5.2. 원인 — 769530b 커밋에서 sync → async로 전환
Swift 6 마이그레이션 커밋(`769530b`)에서 `SiriusServer`가 다음과 같이 바뀌었다.

**이전**
- `public class SiriusServer`
- `serverTransportDidAcceptConnection(_:clientTransport:)`이 sync로 `self.createClientSession(clientTransport)`를 호출
- `createClientSession` 안에서 즉시 `delegate?.siriusServerDidAcceptClientSession(...)` 호출
- 따라서 `rootTransport.simulateClientConnection(...)` 직후 sync하게 delegate가 업데이트되어 있었음

**이후**
- `public actor SiriusServer`
- `nonisolated func serverTransportDidAcceptConnection(...)` 내부에서:
  ```swift
  Task {
      await self.createClientSession(clientTransport)
  }
  ```
- 세션 생성과 delegate 알림이 **Task로 지연**되어 테스트 스레드에 즉시 보이지 않음

`MockServerRoleRootTransport.simulateClientConnection(...)`은 여전히 sync인데, 그 호출 직후 `serverDelegate.acceptedSessions.last!`를 읽으면 Task가 아직 실행되기 전이라 nil이 나오는 race가 생긴 것.

### 5.3. 해결 방향 (후속 TODO)
이 PR의 범위를 벗어나므로 별도 작업으로 남긴다. 제안하는 방식:

1. `ServerTestHarness.simulateClientConnection(...)`을 **async**로 전환
2. 내부에서 `await server.sessions.count`를 expected count와 비교하는 폴링 루프를 돌려 Task 완료를 기다리게 함 (actor 경계를 통과하는 `await`로 직렬화)
3. 모든 호출처 업데이트 (**총 22곳**)
   - `ServerChannelTests.swift` ×5
   - `ServerMainChannelTests.swift` ×3
   - `ServerHandshakeTests.swift` ×3
   - `ServerAuthTests.swift` ×3
   - `ClientSessionCreationTests.swift` ×5
   - `ServerErrorHandlingTests.swift` ×4
4. `ServerErrorHandlingTests.closedTransportIsNotAcceptedAsSession` (L79)은 세션이 **생성되지 않음**을 검증하는 네거티브 테스트다. 단순 폴링으로는 적절한 종료 시점을 알 수 없으므로, 별도 대기 메커니즘(예: `await Task.yield()` 여러 번 + assert, 또는 제한 시간 타임아웃)이 필요.

---

## 6. 검증 결과

```bash
cd SiriusKit && swift test --filter CodecFourCCTests
```
- Build: `Build complete! (3.91s)`
- Tests: `Test run with 15 tests in 1 suite passed after 0.001 seconds.`

§5에서 다룬 서버 테스트(`ServerErrorHandlingTests`, `ClientSessionCreationTests`)는 **빌드는 복구됐으나 런타임 race로 실패**하는 상태. 이는 본 작업 이전부터 잠재해 있던 문제이며, 이번 PR에서는 의도적으로 건드리지 않는다.

---

## 7. 변경 파일 요약

| 파일 | 종류 | 변경 |
| --- | --- | --- |
| `SiriusKit/Tests/.../projection/CodecFourCCTests.swift` | 신규 | 15개 유닛 테스트 추가 |
| `SiriusKit/Tests/.../transport/quic/QUICTransportTest.swift` | 수정 | 로컬 `TestServerDelegate`에 `final` + `@unchecked Sendable` |
| `SiriusKit/Tests/.../server/Mocks/MockSiriusServerDelegate.swift` | 수정 | `@unchecked Sendable` 추가 |
| `SiriusKit/Tests/.../server/Helpers/ServerTestHarness.swift` | 수정 | delegate 설정을 `startup()`의 `await setDelegate(...)`로 이동 |
| `SiriusKit/Tests/.../server/ServerErrorHandlingTests.swift` | 수정 | `harness.server.sessions` → `await harness.server.sessions` (4곳) |
| `SiriusKit/Tests/.../server/ClientSessionCreationTests.swift` | 수정 | 동일 (2곳) |

프로덕션 코드 변경 없음.
