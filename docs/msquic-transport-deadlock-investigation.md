# MsQuic 트랜스포트 데드락 조사 보고서

| 항목 | 내용 |
| --- | --- |
| 작성일 | 2026-05-02 |
| 대상 타겟 | NoctilucaClient (Swift / macOS·iOS), SiriusKitClient (Swift, MsQuic 트랜스포트 어댑터) |
| 대상 컴포넌트 | `ClientRoleMsQuicTransport`, `ClientRoleMsQuicStream`, `SwiftMsQuicAPI`, `QuicConnection`/`QuicStream` (swift-msquic), MsQuic core |
| 대상 의존성 | `swift-msquic` HEAD `9b552f9` (`1.1.3-12`, branch `swift6-concurrency`), MsQuic prebuilt `v2.5.6-tuvariant+260410` |
| 의존 경로 | `SiriusKit/Package.swift:30-31` 의 로컬 path `.package(path: "../../swift-msquic")` |
| 조사 방법 | 멀티 에이전트 협업 — `claude-len` (매니지먼트), `claude-len-siriuskit` (SiriusKit/NoctilucaClient 코드베이스 분석), `openai-codex` (msquic / swift-msquic 코드베이스 분석) |
| 커밋 기준 | `main` 브랜치 head, 작업 트리 (조사 시점) |

본 문서는 Noctiluca Navigator(클라이언트) 가 MsQuic 트랜스포트로 서버에 접속/해제할 때 산발적으로 발생하는
두 가지 데드락 증상의 원인 조사 결과를 정리합니다. 각 원인은 **① 위치 → ② 메커니즘 → ③ 영향 →
④ 권장 조치** 형식으로 다루며, 마지막에 통합 fix roadmap 을 제시합니다.

본 보고서는 **조사** 결과만을 담고 있으며, 본 조사 라운드에서 코드 수정은 수행하지 않았습니다.

---

## 0. TL;DR (요약)

- 두 증상의 root cause 는 단일 원인이 아니라 **두 컴포넌트 (Component A + Component B) 의 결합** 입니다.
- **Component A (Disconnect 경로의 직접 hang)**: ① stream shutdown 에 `.immediate` flag 누락, ② cert validation callback 안 `DispatchQueue.main.sync`, ③ `connectInternal()` throw/cancel 시 partial cleanup 부재.
- **Component B (재연결 시에도 동일 증상 + 앱 재시작 필요 한 누적 leak)**: `SwiftMsQuicAPI.open()` 이 idempotent 가 아니어서 매 connect 마다 **MsQuic API table + `OpenRefCount` 가 누적**되며, Swift wrapper 가 `state.rawAPI` 한 개만 저장하므로 두 번째 open 부터는 이전 pointer 가 overwrite 되어 close 불가능합니다. 또한 SiriusKit 클라이언트 transport 는 대응 `close()` 를 호출하지 않습니다.
- **연결 시 hang (증상 1)** 의 발단은 A2 (cert callback 의 `main.sync` 가 main thread 점유 시 MsQuic worker 를 동기 block) 또는 A3 (cancel 후 partial state 잔존) 이며, 한번 발생하면 B 가 누적되어 앱을 재시작하기 전까지 회복되지 않습니다.
- **연결 해제 hang (증상 2)** 은 A1 (stream `.abort` 가 peer ACK 를 기다리는 wrapper 시맨틱) 의 직접 발현입니다. `disconnectTimeoutMs = 3000` 은 **`connection.shutdown()` await 의 상한이 아니라** outstanding packet 의 path-dead 판정 timer 이므로, worker 가 막히면 무기한 hang 가능합니다.
- **권장 fix**: ① swift-msquic 에 wrapper-level refcount idempotency (W2) 추가 → 누적 leak 차단, ② SiriusKit `quicStream.shutdown(flags: .abort)` → `[.abort, .immediate]` 한 줄 변경, ③ `validateIdentity` 의 `DispatchQueue.main.sync` 제거 후 즉시 deny → 사용자 결정 → 재접속 패턴으로 전환 또는 swift-msquic 에 `ConnectionCertificateValidationComplete` public method 추가 후 `QUIC_STATUS_PENDING` 흐름 채택.

상세 분석은 아래에서 다룹니다.

---

## 1. 증상

### 1-1. 연결 시 데드락

- Noctiluca Navigator 로 접속을 시도할 때 **간헐적**으로 핸드셰이크가 진행되지 않고 멈춤.
- 사용자가 *"연결 취소"* 를 누르면 시도는 중단되지만, **재연결을 시도해도 같은 증상이 반복**됨.
- **앱을 종료하고 다시 실행하기 전까지** 증상이 해소되지 않음.

이 동작은 *"프로세스 내부 어딘가에 stuck 상태가 남아 다음 시도까지 영향을 준다"* 는 신호이며, 단순한 일회성
race 가 아니라 process-wide state 가 회복 불가능한 경로에 들어가는 것을 시사합니다.

### 1-2. 연결 해제 시 데드락 / 매우 긴 종료

- 정상 종료 시퀀스에서도 **간헐적**으로 disconnect 가 무한히 hang 하거나, 수 초~수십 초 동안 진행되지 않음.
- 한 번 hang 한 후에는 증상 1 의 조건과 동일하게 process-wide stuck 으로 이어짐.

---

## 2. 조사 범위 및 방법

### 2-1. 코드 베이스

- `NoctilucaServer` 모노레포 (이 레포): SiriusKit Swift, NoctilucaClient (Navigator).
- `swift-msquic` 외부 path 의존 (`../../swift-msquic`, HEAD `9b552f9`).
- `msquic` 외부 라이브러리 (`v2.5.6-tuvariant+260410`).

### 2-2. 협업 모델

- 채널: `agentalk #noc-msquic-deadlock`.
- 매니지먼트: `claude-len` (Opus 4.7, 본 문서 작성자).
- SiriusKit / NoctilucaClient 분석: `claude-len-siriuskit` (Opus 4.7, 동일 코드 베이스).
- msquic / swift-msquic 분석: `openai-codex` (gpt-5-codex).
- 총 4 라운드의 task 분배 (총 7 task, 2 라운드의 fact-finding + 1 라운드의 가설 정밀화 + 1 라운드의 fix 가능성 검증) 을 거쳐 결론을 도출했습니다.

### 2-3. 한계

- **본 조사는 정적 코드 분석에만 의존**하며, 디버거 / 실행 trace / 재현 시나리오 측정은 수행하지 않았습니다.
- 가설 H1 의 `DispatchQueue.main.sync` 자가 데드락은 정상 async 흐름에서 자발적으로 발현하지 않는 것이 확인되었으므로 *"main thread 가 일시 점유되는 다른 시나리오"* 의 정확한 trigger 는 동적 분석으로 별도 검증되어야 합니다.

---

## 3. 사전 정보

### 3-1. 트랜스포트 어댑터의 실제 구현

`CLAUDE.md` 및 `SiriusKit/CLAUDE.md` 의 *"Network.framework (QUIC)"* 표기는 outdated 입니다. 클라이언트
(macOS / iOS Navigator) 는 swift-msquic 기반 어댑터를 사용합니다.

- `SiriusKit/Sources/SiriusKitClient/client/SiriusClientBuilder.swift:23` — 빌더의 `TransportProtocol.quic(endpoint:)` 가 무조건 `ClientRoleMsQuicTransport` 로 라우팅. 폴백 없음.
- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicTransport.swift` — Swift actor.
- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicStream.swift` — 채널 스트림 wrapper.
- `SiriusKit/Package.swift:30-31` — `.package(path: "../../swift-msquic")` 로 워크스페이스 외부의 swift-msquic 트리를 참조.
- libsirius (C++ MsQuic 바인딩) 는 `NoctilucaClientQt` 전용. macOS Navigator 와는 무관.

### 3-2. 핵심 라이브러리 사실 (msquic / swift-msquic)

#### MsQuic 콜백 / API 모델 (`/msquic/docs/Execution.md`, `/msquic/docs/TSG.md`)

- MsQuic 은 protocol execution 과 app callback 을 **별도 스레드로 분리하지 않음**. callback 안에서 오래 걸리는 작업은 protocol 진행을 그대로 지연시킴.
- 동일 connection (및 그에 속한 stream 들) 의 callback 은 **한 시점에 한 worker thread 에서만 실행**되어 직렬화됨. 동일 객체에 대한 callback 은 parallel 로 들어오지 않음.
- TSG 가 명시한 데드락 원인 패턴:
  1. **MsQuic callback / thread 를 block** 하는 행위.
  2. **MsQuic 호출 중 다른 스레드가 보유한 lock 을 callback 에서 다시 획득** 하는 행위.
- microsoft/msquic#3035 (maintainer 답변): cross-object MsQuic API 호출 (Connection A callback 에서 Connection B API 호출 등) 은 금지. reconnect 는 별도 app thread 에서 해야 함.
- microsoft/msquic#1668 (실제 incident): `ConnectionClose` hang 사례. app thread 가 `ConnectionClose` 호출 중이고 MsQuic worker 는 app callback 에서 막힌 상태였음. 결론: app 이 callback / thread 를 block 하고 있었고 close 호출 방식을 바꿔 해소.

#### Close / Shutdown API blocking semantics (`/msquic/src/core/api.c`)

- `MsQuic->ConnectionClose(...)` 의 동작:
  - worker thread 안에서 호출되면 inline 처리 (`api.c:160-168`).
  - **worker thread 가 아닌 곳에서 호출되면 API operation 을 queue 한 뒤 `CxPlatEventWaitForever` 로 완료를 대기** (`api.c:175-195`). 즉 **blocking API**. worker callback 이 막혀 있으면 close 호출자도 함께 hang.
- `MsQuic->ConnectionShutdown(...)` (`api.c:221-279`): API operation 을 queue 만 하고 기다리지 않음. completion 은 callback (`QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE`) 으로 관측해야 함.
- `MsQuic->StreamClose(...)` 도 같은 패턴 (`api.c:752-803`). worker 외부 호출은 queue + `WaitForever`.
- `MsQuic->StreamShutdown(.IMMEDIATE)` 는 callback / worker thread 안에서 inline 처리 가능 (`api.c:961-980`). 일반 `StreamShutdown` 은 operation queue 후 `QUIC_STATUS_PENDING` 반환.

#### swift-msquic wrapper 핵심 동작

- `QuicConnection.shutdown()` (`/swift-msquic/Sources/SwiftMsQuic/Handlers/QuicConnection.swift:335-367`): 내부 상태를 `.shuttingDown` 으로 바꾸고 `ConnectionShutdown` 호출 후 **`shutdownComplete` callback 까지 continuation 을 보관**. 즉 await 의 resume 시점은 `SHUTDOWN_COMPLETE` event.
- 사용자 `onEvent` handler 는 **MsQuic callback thread 에서 동기 호출** (`QuicConnection.swift:760-768`).
- `peer/transport shutdown initiated` 시 `connectionState` 가 `.shuttingDown / .closed` 로 즉시 바뀌지 **않음** — `.closed` 는 `shutdownComplete` callback 에서야 set (`QuicConnection.swift:803`). 이 사이의 race window 가 microsoft/msquic#4311 (stream leak) 과 매칭.
- `QuicConnection.deinit` 은 pending continuation 을 먼저 resume 한 뒤 마지막에 `api.ConnectionClose(handle)` 호출 (`QuicConnection.swift:869-900`). **마지막 strong reference 가 release 되는 thread 에서 blocking close 가 실행** 됨.
- `QuicStream.shutdown(flags: .abort)` 기본은 `.abort` 만 사용하고 `.immediate` 를 자동 추가하지 않음 (`QuicStream.swift:366-405`). completion callback 까지 await.
- `QuicStream.deinit` 도 마지막에 blocking `StreamClose` 호출 (`QuicStream.swift:485-508`).
- `QuicRegistration.deinit` 의 `RegistrationClose` 는 **child close 까지 block 하며 callback 에서 호출하면 deadlock 가능** 하다는 주석이 wrapper 자체에 있음 (`QuicRegistration.swift:87-92`).

#### MsQuic library global state (`/msquic/src/core/library.c`)

- `MsQuicOpenVersion(...)` (`library.c:1980-2017`): 매 호출마다 `MsQuicAddRef()` 후 `QUIC_API_TABLE` 을 새로 alloc, out param 에 새 pointer 기록 (`library.c:2071`).
- `MsQuicAddRef()` (`library.c:715-742`): `OpenRefCount` 를 증가시키고 **1 이 될 때만** 전역 library state 를 initialize.
- `MsQuicClose(api)` (`library.c:2094-2105`): 받은 API table 을 free 하고 `MsQuicRelease()` 로 refcount 를 1 내림.
- `MsQuicRelease()` (`library.c:757-775`): `OpenRefCount` 가 0 이 될 때만 global library 를 uninitialize.

이 사실들은 *"여러 번 open 해도 OpenRefCount 가 늘어날 뿐, 첫 open 의 worker pool 은 그대로 유지된다"* 는 의미이며, Component B 의 메커니즘 핵심입니다.

---

## 4. Component A — Disconnect 경로의 직접 hang

### 4-1. A1: stream shutdown 에 `.immediate` 누락

#### 위치

- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicStream.swift:45-52`

```swift
public func close() async throws {
    ...
    await quicStream.shutdown(flags: .abort)
    ...
}
```

#### 메커니즘

- `swift-msquic` 의 `QuicStream.shutdown(flags:)` 은 `MsQuicStreamShutdown` 호출 후 `QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE` 이벤트가 와야 continuation 이 resume 됩니다.
- `MsQuicStreamShutdown` 의 `IMMEDIATE` 가 빠진 일반 abort 는 **`LocalCloseAcked && RemoteCloseAcked`** 등 양방향 close ACK 조건을 기다린 뒤 `SHUTDOWN_COMPLETE` 를 indicate 합니다 (`/msquic/src/core/stream.c:596-639`).
- 즉 *"abort"* 라는 이름과 달리, peer 의 ACK 가 오지 않으면 wrapper await 가 풀리지 않습니다.
- `IMMEDIATE` flag 는 API validation 상 `IMMEDIATE | ABORT_RECEIVE | ABORT_SEND` 조합에서만 유효합니다 (`/msquic/src/core/api.c:940-945, 1005-1009`). 따라서 Swift 의 `[.abort, .immediate]` 는 valid (단방향 immediate 는 invalid).
- `.immediate` 가 추가되면 send/receive shutdown complete 와 stream shutdown complete event 가 즉시 indicate 됩니다 (`/msquic/src/core/api.c:1955-2011`).

#### 영향

- Disconnect 시 `ClientRoleMsQuicTransport.disconnect()` (`ClientRoleMsQuicTransport.swift:164-181`) 가 stream snapshot 을 순차적으로 `await stream.close()` 처리합니다. 한 stream 의 SHUTDOWN_COMPLETE 가 늦으면 **전체 disconnect 가 그 stream 에 발목이 잡힘**.
- 이후 `await connection.shutdown()` 까지 도달하지 못함.
- 증상 2 (*"연결 해제 hang / 느림"*) 의 직접 발현 메커니즘.

#### 권장 조치

- `quicStream.shutdown(flags: [.abort, .immediate])` 로 한 줄 변경.
- abort 의 abrupt close 시맨틱은 변경되지 않으며, *"local completion 대기 ↔ peer ACK"* 의 결합만 끊어집니다.
- 데이터 무결성: 이미 `.abort` 가 abrupt close 의도이므로 `.immediate` 추가는 **새로운 무결성 문제를 만들지 않습니다**.

### 4-2. A2: cert validation callback 안 `DispatchQueue.main.sync`

#### 위치

- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicTransport.swift:289`

```swift
private static func validateIdentity(...) -> ServerIdentityTrustDecision {
    ...
    if policy.requiresAppValidation, let block = policy.validationBlock {
        return DispatchQueue.main.sync {
            block(identity)
        }
    }
    ...
}
```

호출 경로:
1. swift-msquic 의 `connection.onPeerCertificateReceived` 콜백이 동기로 호출됨 (`ClientRoleMsQuicTransport.swift:300-320`).
2. 콜백 closure 안에서 `Self.validateIdentity(...)` 동기 호출.
3. `validateIdentity` 가 `DispatchQueue.main.sync { block(identity) }` 호출.

#### 메커니즘

- macOS / iOS 경로에서 cert validation callback 은 `quictls` → `SecConfig->Callbacks.CertificateReceived(...)` 로 들어옵니다 (`/msquic/src/platform/tls_quictls.c:355-361`).
- core 측에서는 `QuicConnPeerCertReceived` 가 `QUIC_CONNECTION_EVENT_PEER_CERTIFICATE_RECEIVED` 를 app callback 에 **동기 upcall** 하며, callback return status 를 즉시 해석합니다 (`/msquic/src/core/connection.c:3156-3200`).
- 이 callback 이 return 할 때까지 TLS / crypto 처리는 진행되지 않습니다 (`/msquic/src/core/crypto.c:1843-1857, 1962-1970`).
- 즉 callback 은 **MsQuic worker thread 위에서 동기로 실행** 되며 그 동안 worker 는 protocol 진행을 멈춥니다.
- `DispatchQueue.main.sync` 는 isolation hop 이 아니라 calling thread 를 blocking 하는 GCD sync 입니다. main 이 즉시 비어 있으면 짧게 끝나지만, **main thread 가 점유되어 있으면 worker thread 가 그 점유 시간만큼 block** 됩니다.
- TSG 관점에서 **위험 패턴** 입니다 (Section 3-2 의 두 번째 데드락 패턴).
- `NoctilucaClient` 의 `validationBlock` 본체에는 자가 데드락 패턴이 없는 것이 확인되었습니다 (`NoctilucaClient/.../NoctilucaClient.swift:265-301`):
  - `MainActor.assumeIsolated` 사용 (추가 hop 없음).
  - `uiEvents.send(...)` 동기 send.
  - `identity.fingerprint()` 동기 작업.
  - 따라서 *"항상 hard-deadlock"* 은 아니며, **main 이 일시 점유될 때만 발현되는 조건부 hang** 입니다. *"가끔"* 의 정체.

#### 영향

- main thread 가 어떤 사유로든 점유되어 있는 시점 (예: AppKit modal, 동기적 UI 작업, 다른 await 의 main hop 경합) 에 cert callback 이 발생하면 **MsQuic worker thread 가 main 의 점유가 풀릴 때까지 block**.
- 그 동안 같은 worker 가 담당하는 다른 connection 의 protocol 진행도 함께 멈춥니다 (Section 3-2 의 직렬화 모델).
- 한 번 발생하면 Component B 가 누적되므로 재시도해도 동일 증상.

#### 권장 조치

- 단기: **`DispatchQueue.main.sync` 를 제거** 하고, callback 안에서는 main / UI 가 필요 없는 검증 (fingerprint / SPKI pinning / allowlist 비교) 만 동기 수행. UI 결정이 필요하면 즉시 `.badCertificate` 로 deny 하고, 사용자 결정 후 allowlist 갱신 → 재접속 패턴으로 분리.
- 중기: swift-msquic 에 `ConnectionCertificateValidationComplete` public method 를 추가하고, callback 에서 `QUIC_STATUS_PENDING` 을 반환한 뒤 비동기로 결정 결과를 complete 하는 패턴으로 전환 (Section 6-3 참조).

### 4-3. A3: `connectInternal()` throw / cancel 시 partial cleanup 부재

#### 위치

- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicTransport.swift:74-145`

```swift
private func connectInternal() async throws {
    await setupAddressMonitor()                             // 1
    _ = SwiftMsQuicAPI.open()                               // 2
    let registration = try QuicRegistration(...)            // 3 ← throw 가능
    self.registration = registration
    var settings = QuicSettings()
    ...
    let configuration = try QuicConfiguration(...)          // 4 ← throw 가능
    self.configuration = configuration
    ...
    try configuration.loadCredential(credential)            // 5 ← throw 가능
    let connection = try QuicConnection(...)                // 6 ← throw 가능
    try connection.setStreamSchedulingScheme(.roundRobin)   // 7 ← throw 가능
    self.connection = connection
    await setupEventHandlers(connection)
    try await connection.start(...)                         // 8 ← throw / cancel 가능
    ...
}
```

#### 메커니즘

- 모든 throw 경로에 catch / partial cleanup 이 없습니다.
- 3~7 사이 throw 시 `self.registration` / `self.configuration` 가 부분적으로 set 된 채 actor 안에 잔존. 다음 `connectInternal()` 호출 시 덮어씌워지지만 이전 핸들은 swift-msquic 측에서 close 되지 않은 상태.
- 8 (`connection.start`) 도중 사용자 cancel → `CancellationError` throw → swift-msquic connection 핸들이 in-flight 상태에서 dangling.
- transport actor 가 release 되어도 swift-msquic worker thread 가 callback closure 를 retain 하면 그 closure 가 retain 한 connection 객체가 살아있게 됩니다.
- `disconnect()` 의 partial state 처리 (`ClientRoleMsQuicTransport.swift:164-194`):

```swift
if let connection = self.connection {
    await connection.shutdown()       // partial 상태에서도 호출 시도
    self.connection = nil
}
```

  partial connection 에 shutdown 을 부르면 swift-msquic 측이 어떻게 동작하는지가 명확하지 않습니다 (정의되지 않은 동작 영역).

#### 영향

- Cancel / throw 후 actor 안에 dangling 상태 잔존 → 다음 connect 시 새 객체로 덮어쓰여지지만 이전 객체의 swift-msquic 자원은 close 안 됨.
- Component B 의 누적 leak 과 결합하여 process-wide stuck 의 발단이 됩니다.

#### 권장 조치

- `connectInternal()` 을 `do { ... } catch { await partialCleanup(); throw }` 형태로 감싸고, `partialCleanup` 에서 set 된 객체들을 역순으로 close / nil 처리.
- partial connection 에 `shutdown()` 을 부르는 대신 `close` (강제 release) 또는 nil 처리만 수행하는 분기를 두는 것이 안전.

---

## 5. Component B — `SwiftMsQuicAPI.open()` 누적 leak

이 컴포넌트는 *"재연결을 시도해도 같은 증상이 반복되며 앱을 재시작해야만 회복된다"* 는 증상 1의 후반부의 직접 메커니즘입니다.

### 5-1. B1: `SwiftMsQuicAPI.open()` 이 idempotent 가 아님

#### 위치

- `swift-msquic/Sources/SwiftMsQuic/SwiftMsQuicAPI.swift:77-80`

```swift
public static func open() -> QuicStatus {
    return MsQuicOpenVersion(...&state.rawAPI)
}
```

#### 메커니즘

- `state.rawAPI` 가 이미 set 되어 있는지 확인하지 않고 매 호출마다 `MsQuicOpenVersion(...)` 을 호출합니다.
- MsQuic core 측 동작 (Section 3-2 참조):
  - 매 호출마다 `MsQuicAddRef()` → `OpenRefCount` 가 1 증가.
  - `QUIC_API_TABLE` 을 새로 alloc 하여 out param (`state.rawAPI`) 에 기록.
- Swift wrapper 가 `state.rawAPI` 한 슬롯만 가지므로, **두 번째 `open()` 호출은 이전 API table pointer 를 overwrite**. 이전 pointer 는 더 이상 close 할 수 없으므로 **API table + OpenRefCount 가 영구 leak**.

### 5-2. B2: SiriusKit 클라이언트는 매 connect 마다 `open()` 을 호출하고 close 는 호출하지 않음

- `SiriusKit/.../ClientRoleMsQuicTransport.swift:78` — `connectInternal()` 안에서 `_ = SwiftMsQuicAPI.open()` 호출.
- `rg`/`grep` 결과 SiriusKit client transport 어디에도 `SwiftMsQuicAPI.close()` 호출 없음. `disconnect()` 는 connection / configuration / registration 을 nil 로 만들지만 API table 자체는 close 하지 않습니다.
- `NoctilucaServer/utils/MsQuicLoader.swift:13` 의 `static let shared = ...` 는 서버 측 path 에서 한 번 open 을 보장하지만, **클라이언트 측 `ClientRoleMsQuicTransport.connectInternal()` 은 그것과 무관하게 매번 open 을 추가로 호출** 합니다.

### 5-3. B3: `OpenRefCount > 0` 인 동안 MsQuic global state 는 재초기화되지 않음

- `MsQuicAddRef()` 는 `OpenRefCount == 1` 일 때만 global library state 를 initialize 합니다.
- `MsQuicRelease()` 는 `OpenRefCount == 0` 이 될 때만 global library 를 uninitialize 합니다.
- 따라서 **이미 broken state 로 들어간 worker / registration / global timer 가 있어도, 두 번째 open 은 그 상태를 복구하지 않습니다**. 새 API table pointer 만 받게 될 뿐입니다.

### 5-4. B4: 종합 메커니즘

1. 첫 connect 가 비정상 종료 (A2 또는 A3). 일부 worker 또는 registration 이 *busy* 상태로 남음.
2. 사용자가 *"취소"* → cleanup 일부 진행, 그러나 A3 의 partial cleanup 부재로 swift-msquic 자원이 dangling.
3. 사용자가 재연결 시도. `connectInternal()` 이 다시 호출 → `_ = SwiftMsQuicAPI.open()` 으로 **OpenRefCount 가 또 증가** 하고 새 API table 이 alloc 되며 이전 pointer 는 unreachable.
4. 새 transport / 새 API table 가 만들어지지만, MsQuic global library / worker pool / 이전 connection 의 처리 상태는 그대로 stuck. **handshake 가 같은 worker 에 큐잉되거나, 같은 timer slot 을 기다리는 형태로 다시 hang**.
5. 앱 종료 시 process kill 로 모든 자원이 강제 cleanup → 다음 실행에서 *"앱 재시작 후 정상 동작"*.

### 5-5. 영향

- 증상 1 (*"재연결 시 같은 증상 + 앱 재시작 필요"*) 의 직접 메커니즘.
- swift-msquic 자체의 약점이라 **SiriusKit 측만 수정해서는 완전 해결 불가**. swift-msquic 도 함께 변경되어야 합니다.

### 5-6. 권장 조치

- swift-msquic 에 wrapper-level refcount idempotency 적용 (옵션 W2):

```swift
// 의사 코드
struct ApiState {
    var rawAPI: ...
    var openCount: Int
}

public static func open() -> QuicStatus {
    lock.lock(); defer { lock.unlock() }
    if state.rawAPI != nil {
        state.openCount += 1
        return .success
    }
    let status = MsQuicOpenVersion(...&state.rawAPI)
    if status.succeeded { state.openCount = 1 }
    return status
}

public static func close() {
    lock.lock(); defer { lock.unlock() }
    guard state.openCount > 0 else { return }   // 또는 assertion
    state.openCount -= 1
    if state.openCount == 0, let api = state.rawAPI {
        MsQuicClose(api)
        state.rawAPI = nil
    }
}
```

- 장점: 기존 `open() / close()` 호출 계약을 보존. 다중 사용자 (server / client / tests / multi-transport) 가 공존해도 안전. 반복 `open()` 이 더 이상 API table / OpenRefCount 를 누적하지 않음.
- 단점: 호출자가 close 를 빠뜨리면 process lifetime 동안 open 상태가 유지됩니다. 그러나 현재 문제인 누적 leak 은 막습니다.

대안 W1 (`static let shared = ... ` 식 process singleton, close 는 process 종료 시까지 안 함) 은 close semantics 가 모호해져 server role 등 다른 사용 패턴에 약점이 있어 권장하지 않습니다.

`swift-msquic` 의 git log 상 maintainer 는 `Gyuhwan Park <unstabler@unstabler.pl>` 로 본 프로젝트 author 와 동일하므로 fork / patch 부담은 낮습니다.

---

## 6. 두 증상의 매핑

### 6-1. 증상 1: 연결 시 hang + 재연결도 hang + 앱 재시작 필요

```
[user] connect ──▶ ClientRoleMsQuicTransport.connectInternal()
                       │
                       │  _ = SwiftMsQuicAPI.open()      ← OpenRefCount++ + API table alloc (B)
                       │
                       │  swift-msquic 핸드셰이크 ──▶ MsQuic worker
                       │                                   │
                       │                            cert callback (sync)
                       │                                   │
                       │                            DispatchQueue.main.sync (A2)
                       │                                   │
                       │     [main 일시 점유 시] ◀─────── worker block
                       │                                   │
                       │                              handshake stall
                       │                                   │
[user] cancel ────────▶│                                   │
                       │ throw CancellationError (A3)      │
                       │ → partial state 잔존              │
                       └─────────────────────────── (worker / registration dangling)

[user] retry ────▶ connectInternal()
                       │
                       │  _ = SwiftMsQuicAPI.open()  ← 이전 API table overwrite (B)
                       │                              OpenRefCount += 1, 누적
                       │
                       │  새 connection ──▶ MsQuic worker (여전히 stuck or busy)
                       │
                       └─ 같은 증상 재현
```

발단: A2 또는 A3.
누적: B1~B4.
회복: 앱 재시작 (process kill).

### 6-2. 증상 2: 연결 해제 hang / 매우 느림

```
disconnect()
   │
   ├── for stream in streams: await stream.close()
   │       │
   │       └── await quicStream.shutdown(flags: .abort)  ← .immediate 누락 (A1)
   │              │
   │              └── peer ACK 대기 → 한 stream 늦으면 전체 늦어짐
   │
   ├── (전체 stream close 완료 후) await connection.shutdown()
   │       │
   │       └── ConnectionShutdown queue → SHUTDOWN_COMPLETE callback await
   │              │
   │              └── disconnectTimeoutMs 가 timeout 보장 ❌
   │                   (그것은 outstanding packet path-dead timer)
   │
   └── partial state 또는 worker block 시 무한 hang 가능
```

직접 원인: A1.
보조 원인: A2 가 worker block 중이면 connection.shutdown() 도 hang. B 가 누적된 상태면 cleanup 도 hang.

### 6-3. cert validation 의 PENDING 패턴 (참고)

MsQuic 이 권장하는 비동기 cert validation 의 표준 패턴은 다음과 같습니다 (`/msquic/docs/api/ConnectionCertificateValidationComplete.md`):

1. App 의 cert callback 이 `QUIC_STATUS_PENDING` 을 return.
2. MsQuic core 가 `CertValidationPending = TRUE` 로 만들고 TLS / crypto 처리를 잠시 멈춤 (`/msquic/src/core/crypto.c:1843-1857`).
3. App 이 비동기로 결정 (UI 등) 후 `MsQuic->ConnectionCertificateValidationComplete(handle, result, alert)` 호출.
4. MsQuic 이 pending 을 해제하고 handshake 진행.

현재 `swift-msquic` 의 상황:

- `QuicStatus.pending` public 으로 정의되어 있고, `QuicConnection.handleEvent` 가 handler 반환값을 그대로 전달하므로 **`.pending` 반환은 wrapper 레벨에서 가능**.
- 그러나 `MsQuicApi`, `QuicObject.api`, `handle` 이 모두 `internal` 이고, `QuicConnection` public method 로 cert validation complete 가 노출되어 있지 않습니다. **외부 모듈 (SiriusKit) 에서 `ConnectionCertificateValidationComplete` 를 호출할 수 없습니다**.
- 따라서 PENDING + complete 패턴을 SiriusKit 만 수정해서 적용할 수는 없습니다.

채택하려면 swift-msquic 에 다음과 같은 minimal 변경이 필요합니다:

```swift
// QuicConnection 에 추가 (예시)
public func completeCertificateValidation(
    result: Bool,
    tlsAlert: QuicTlsAlertCode = .success
) -> QuicStatus {
    guard let handle else { return .invalidState }
    return api.ConnectionCertificateValidationComplete(
        handle, result ? TRUE : FALSE, tlsAlert
    )
}
```

주의:
- `ConnectionCertificateValidationComplete` 는 operation 을 queue 하고 `QUIC_STATUS_PENDING` 을 반환할 수 있으므로 wrapper 의 `throwIfFailed()` 가 이 값을 실패로 보면 안 됩니다. 다행히 `QuicStatus.succeeded` 정의가 `<= 0` 이라 `.pending` 도 succeeded 로 취급됩니다 (`QuicStatus.swift:96-98`).
- Lifecycle: cert callback 이 `.pending` 을 반환한 후 connection 객체를 strong capture 한 async Task 를 살려 두어야 complete 가 호출될 때까지 핸들이 유효합니다. complete 는 idle / disconnect timeout 전에 호출되어야 합니다.
- Darwin 경로는 cert / chain 을 `SecCertificate` 로 복사하므로 async 사용이 비교적 안전합니다 (raw certificate pointer 가 callback 동안만 valid 인 non-Darwin 경로와 다름).

---

## 7. 보조 발견 사항 (관련 cleanup leak)

본 조사 과정에서 root cause 와 직접 연결되지는 않으나 같은 라이프사이클 경로에서 함께 발견된 leak 한 건을 기록합니다.

### 7-1. `stopSession(force: false)` 의 early return 으로 인한 RemoteSessionManager / ViewModel.remoteSession leak

#### 위치

- `NoctilucaClient/.../SessionWindowViewModel.swift:213-245`

```swift
private func stopSession(force: Bool = false) async {
    ...
    guard let client = remoteSession?.client else { return }
    if !force && client.isValidatingServerIdentity { return }   // ← early return
    ...
    detachRemoteSession()
}
```

#### 메커니즘

1. cert deny 경로에서 `validationBlock` 이 `isValidatingServerIdentity = true` 로 set 한 뒤 (`NoctilucaClient.swift:265-301`) `succeedValidationDecision == nil` 일 때 `defer { isValidatingServerIdentity = false }` 가 적용되지 않음 (이 분기에는 defer 가 없음).
2. transport 가 `.deny` 응답 후 자동 close 되어 `phase = .closed` 발화.
3. `SessionWindowViewModel.handleClientPhaseChanged(.closed)` (`SessionWindowViewModel.swift:305-308`) 이 `Task { @MainActor in await self.stopSession() }` 를 호출 (force=false 기본값).
4. `stopSession` 의 early return 으로 `detachRemoteSession()` 호출되지 않음 → `RemoteSessionManager.shared.sessions[id]` 와 `viewModel.remoteSession` 의 strong ref 가 잔존.

`NoctilucaClientManager.shared.clients` 는 `NoctilucaClient.close()` 가 직접 `detachClient(id:)` 를 호출하므로 정상 cleanup 됩니다 (`NoctilucaClient.swift:589`). 누락은 `RemoteSessionManager.sessions` 와 ViewModel 측의 strong ref 입니다.

#### 영향

- 메모리 leak 수준이며, swift-msquic level 자원은 이미 `NoctilucaClient.close()` 안 detached `transport.disconnect()` 로 시도되므로 deadlock 의 직접 원인은 아닙니다.
- 정상 흐름 (사용자가 다이얼로그에서 결정 → 재접속) 에서는 `cleanupForReconnect` (`SessionWindowViewModel.swift:285-291`) 가 detachRemoteSession + killClient 를 처리하므로 leak 없음.
- 비주류 시나리오 (사용자가 다이얼로그를 띄운 채 윈도우 닫음 등) 에서 누적 가능.

#### 권장 조치

- `stopSession(force: false)` 의 early return 조건을 재검토. `isValidatingServerIdentity` 가 *"cleanup 을 일시적으로 미루는 의도"* 라면, validation 결정 또는 cancel 시 명시적으로 cleanup 을 트리거하는 경로가 따로 있어야 합니다.
- 또는 `validationBlock` 의 `succeedValidationDecision == nil` 분기에도 `defer { isValidatingServerIdentity = false }` 를 적용하여 플래그가 stuck 되지 않도록 정리.

### 7-2. `SiriusClient.shutdown()` 의 HACK 코멘트

- `SiriusKit/Sources/SiriusKitClient/client/SiriusClient.swift:72-84`:

```swift
public func shutdown() async {
    ...
    await channelManager.teardownAllChannels()

    // HACK: 별도 Task로 분리하지 않으면 여기서 데드락 걸림
    Task.detached { [clientTransport] in
        await clientTransport.disconnect()
    }
}
```

- 이 우회 패턴은 **호출자를 풀어줄 뿐 swift-msquic 측 hang 자체는 그대로 유지** 합니다. 즉 transport.disconnect() 가 hang 하면 detached Task 만 살아남고, swift-msquic 자원은 점유된 상태로 남습니다. 이것이 Component B 의 누적 시작점이 됩니다.
- 본 보고서의 권장 fix (Section 9) 가 적용되면 disconnect() 의 hang mechanism 자체가 제거되므로 이 HACK 의 부담도 줄어듭니다. 다만 peer-initiated shutdown 등 detached 우회가 미적용되는 경로는 여전히 남으므로, 향후 라이프사이클 정리 시 함께 검토되어야 합니다.

---

## 8. `disconnectTimeoutMs = 3000` 에 대한 오해 정정

`SiriusKit/.../ClientRoleMsQuicTransport.swift` 의 `settings.disconnectTimeoutMs = 3000` 설정은 다음 방식으로 전달됩니다.

- swift-msquic 의 `QuicSettings` 가 `QUIC_SETTINGS.DisconnectTimeoutMs` 에 값을 넣고 `IsSetFlags` bit 를 set (`/swift-msquic/Sources/SwiftMsQuic/Configuration/QuicSettings.swift:266-269`).
- `QuicConfiguration` 이 non-nil settings 일 때 `ConfigurationOpen(...)` 으로 전달 (`QuicConfiguration.swift:92-99`).
- 즉 **전달 자체는 정상 OK**.

그러나 그 의미는 흔히 오해되는 *"connection.shutdown() 의 응답 timeout"* 이 **아닙니다**:

- `DisconnectTimeoutMs` 의 정의는 *"ACK 를 기다리다가 path 를 dead 로 선언하기까지의 시간"* (`/msquic/docs/Settings.md:30-45`).
- core 의 loss detection 도 이를 *"outstanding packet 이 ACK / loss 판정 없이 남아 있을 때 connection 을 terminate 하는 last-resort give-up timer"* 로 설명 (`/msquic/src/core/loss_detection.c:24-30, 344-358, 1838-1850`).
- local close 경로에는 별도로 `QuicLossDetectionComputeProbeTimeout(..., QUIC_CLOSE_PTO_COUNT)` 의 close PTO timer (`QUIC_CLOSE_PTO_COUNT = 3`) 가 있어, peer 가 close 에 응답하지 않아도 결국 closed 로 간주되고 `SHUTDOWN_COMPLETE` 가 발화됩니다 (`/msquic/src/core/connection.c:1551-1565, 1710-1724`).

따라서 healthy worker 라면 `connection.shutdown()` 이 결국 풀리지만, **그 시간은 `DisconnectTimeoutMs` 그 자체가 아니라 close PTO + RTT / RttVariance / MaxAckDelay 의 함수**이며, **3 초 상한은 보장되지 않습니다**.

특히 worker thread 가 어떤 callback (예: A2 의 `main.sync`) 에 잡혀 있어 timer / queued operation 을 drain 하지 못하면 `DisconnectTimeoutMs` 자체가 발현되지 않으므로 **무기한 hang 가능**.

→ **app-level timeout / cancel cleanup 정책이 별도로 필요합니다** (예: `try await withTimeout(seconds: 3) { connection.shutdown() }` 후 timeout 시 강제 release 경로).

---

## 9. 권장 fix 우선순위

| Pri | Fix | Repo | 변경 위치 | 예상 변경량 |
| --- | --- | --- | --- | --- |
| **P0** | swift-msquic 에 wrapper-level refcount idempotency 적용 (W2) | swift-msquic | `Sources/SwiftMsQuic/SwiftMsQuicAPI.swift` | 중간 (state struct + open / close 분기) |
| **P1** | `quicStream.shutdown(flags: [.abort, .immediate])` | NoctilucaServer | `SiriusKit/.../ClientRoleMsQuicStream.swift:45-52` | 한 줄 |
| **P1** | `validateIdentity` 의 `DispatchQueue.main.sync` 제거 → 즉시 deny → 재접속 패턴 | NoctilucaServer | `SiriusKit/.../ClientRoleMsQuicTransport.swift:289` 부근 + `NoctilucaClient.swift:265-301` 의 validationBlock 본체 | 작음~중간 |
| **P2** | `connectInternal()` throw / cancel cleanup 보강 | NoctilucaServer | `SiriusKit/.../ClientRoleMsQuicTransport.swift:74-145` | 중간 (do-catch + partialCleanup 함수) |
| **P2** | `connection.shutdown()` 에 app-level timeout 적용 | NoctilucaServer | `SiriusKit/.../ClientRoleMsQuicTransport.swift:179` | 작음 |
| **P3** | swift-msquic 에 `completeCertificateValidation(...)` public method 추가 + SiriusKit 측 PENDING + complete 흐름 채택 | swift-msquic + NoctilucaServer | `swift-msquic/.../QuicConnection.swift` + SiriusKit cert 흐름 재설계 | 중간 (UX 개선 큰 fix) |
| **P3** | `stopSession(force: false)` early return + `validationBlock` defer 정리 | NoctilucaServer | `SessionWindowViewModel.swift:213-245`, `NoctilucaClient.swift:265-301` | 작음 |

### 9-1. 최소 적용 범위

P0 + P1 (stream `.immediate`) + P1 (cert sync 제거) 만 적용해도 두 증상의 메커니즘이 차단됩니다:

- P0 → Component B (누적 leak) 차단. 한 번 hang 이 발생해도 process-wide 누적이 발생하지 않으므로 *"앱 재시작 필요"* 증상 자체가 사라집니다.
- P1 (stream `.immediate`) → A1 의 직접 hang 차단. 종료 hang / 느림 (증상 2) 이 사라집니다.
- P1 (cert sync 제거) → A2 의 worker thread block 차단. 연결 시 hang (증상 1 의 발단) 가능성이 크게 줄어듭니다.

### 9-2. 비최소 적용 시 추가 효과

- P2 cleanup 보강: 이상 종료 후의 자원 누수가 명시적으로 정리됩니다.
- P2 app-level timeout: worker block 등 비정상 상황에서도 사용자 인지 가능한 시간 안에 disconnect 가 풀립니다.
- P3 PENDING + complete 흐름: 사용자 결정 UX 가 *"즉시 deny 후 재접속"* 보다 부드러워집니다.

---

## 10. 미해결 / 후속 검증 항목

본 조사는 정적 분석에 한정되어 다음 항목은 추가 검증이 필요합니다.

1. **A2 의 정확한 trigger**: main thread 가 어떤 시점에 점유되어 cert callback 의 `main.sync` 가 멈추는지. AppKit modal, NSAlert 류 동기 UI, 다른 await 의 main hop 경합 등 후보가 있으나 동적 분석으로 재현이 필요합니다.
2. **B4 의 누적 횟수와 worker pool 의 정확한 stuck 형태**: 첫 hang 이후 N 회 재연결 시 swift-msquic / msquic 의 어떤 객체 (registration / configuration / connection / 내부 worker thread) 가 어떤 상태로 잔존하는지의 동적 trace.
3. **`SiriusClient.shutdown()` 의 HACK 코멘트가 처음 추가된 시점의 재현 시나리오**: git blame 으로 commit 을 찾아 그 시점에 보인 stack trace / 재현 절차를 확인하면 우회 대신 root fix 의 방향이 더 명확해집니다.
4. **`onPeerCertificateReceived` callback 안의 `nonisolated(unsafe) var` 들의 race**: validation 완료 신호가 다른 callback 과 interleave 될 가능성이 있으나, 본 조사에서는 단일 connection callback 의 직렬화 보장 (Section 3-2) 으로 *"실질적 race 는 없음"* 으로 잠정 분류했습니다. 동적 측정으로 재확인이 필요합니다.

---

## 11. 부록 — 참고 파일 목록

### NoctilucaServer / SiriusKit / NoctilucaClient

- `SiriusKit/Package.swift:30-31`
- `SiriusKit/Sources/SiriusKitClient/client/SiriusClientBuilder.swift:23`
- `SiriusKit/Sources/SiriusKitClient/client/SiriusClient.swift:69-84`
- `SiriusKit/Sources/SiriusKitClient/transport/client/ClientRoleTransport.swift:144-149`
- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicTransport.swift:74-145, 164-194, 196-203, 240, 288-320, 323-357`
- `SiriusKit/Sources/SiriusKitClient/transport/client/msquic/ClientRoleMsQuicStream.swift:45-52`
- `SiriusKit/Sources/SiriusKitCore/channel/ChannelHandle.swift:143, 168, 298-332`
- `SiriusKit/Sources/SiriusKitCore/channel/ChannelManager.swift:290-322`
- `SiriusKit/Sources/SiriusKitClient/osapi/network/AddressMonitor.swift:117`
- `NoctilucaServer/utils/MsQuicLoader.swift:13`
- `NoctilucaClient/NoctilucaClient/core/logic/NoctilucaClient.swift:151, 223, 262-311, 562-590, 593-605`
- `NoctilucaClient/NoctilucaClient/core/logic/NoctilucaClientManager.swift:26-66`
- `NoctilucaClient/NoctilucaClient/core/state/RemoteSession.swift:14-96`
- `NoctilucaClient/NoctilucaClient/core/state/RemoteSessionManager.swift:14-35`
- `NoctilucaClient/NoctilucaClient/core/ui/main/viewmodels/SessionWindowViewModel.swift:172-211, 213-245, 285-291, 305-308`

### swift-msquic (`../../swift-msquic`, HEAD `9b552f9`)

- `Sources/SwiftMsQuic/SwiftMsQuicAPI.swift:42-45, 77-93`
- `Sources/SwiftMsQuic/Handlers/QuicConnection.swift:178-184, 335-367, 716-828, 855-860, 869-900`
- `Sources/SwiftMsQuic/Handlers/QuicStream.swift:366-405, 466-476, 485-508`
- `Sources/SwiftMsQuic/Configuration/QuicSettings.swift:266-269`
- `Sources/SwiftMsQuic/Configuration/QuicConfiguration.swift:92-99`
- `Sources/SwiftMsQuic/Configuration/QuicRegistration.swift:87-92`
- `Sources/SwiftMsQuic/Utilities/QuicFlags.swift:126-148`
- `Sources/SwiftMsQuic/Core/QuicStatus.swift:96-98`

### msquic (`v2.5.6-tuvariant+260410`)

- `src/inc/msquic.h:222-230, 1518-1531, 1800-1836`
- `src/core/library.c:715-777, 1980-2105`
- `src/core/api.c:120-195, 221-279, 752-803, 940-980, 1005-1009, 1955-2011`
- `src/core/connection.c:1367-1427, 1516-1572, 1636-1642, 1690-1705, 3156-3200`
- `src/core/crypto.c:1715-1723, 1843-1857, 1962-1970`
- `src/core/loss_detection.c:24-30, 344-358, 1838-1850`
- `src/core/stream.c:596-639`
- `src/platform/tls_quictls.c:355-361`
- `docs/Execution.md:59-89`
- `docs/TSG.md:189-229`
- `docs/Settings.md:30-45`
- `docs/Streams.md:38-45`
- `docs/api/StreamShutdown.md:31-56`
- `docs/api/StreamClose.md:26-31`
- `docs/api/ConnectionClose.md:28-35`
- `docs/api/ConnectionCertificateValidationComplete.md:1-5`

### GitHub issues (참고)

- microsoft/msquic#3035 — cross-object MsQuic API 호출 금지 / reconnect 는 별도 thread.
- microsoft/msquic#1668 — `ConnectionClose` hang 사례, app callback block 이 원인.
- microsoft/msquic#4180 — send buffer 재사용 / callback blocking 의 함정.
- microsoft/msquic#4311 — `MsQuicStreamOpen` + `MsQuicConnectionShutdown` race / stream leak.
