# ClipboardChannel / TransferChannel 보안 감사 보고서

| 항목 | 내용 |
| --- | --- |
| 작성일 | 2026-04-10 |
| 대상 타겟 | NoctilucaServer (Swift / macOS), NoctilucaClient (Swift / macOS·iOS), NoctilucaClientQt (C++ / Linux·Windows) |
| 대상 feature | `SiriusFeature.clipboard` (UUID `8A3D9F2E-…`), `SiriusFeature.transfer` (UUID `9F4EE026-…`) |
| 대상 프로토콜 | SiriusKit msgdef `msgdef/v1/channels/clipboard.proto`, `msgdef/v1/channels/transfer.proto` |
| 커밋 기준 | `migrate-to-swift6` 브랜치 작업 트리(조사 시점) |

본 문서는 Noctiluca 의 클립보드 동기화(ClipboardChannel)와 부수적인 대용량 데이터 전송(TransferChannel)
경로를 세 타겟(서버 Swift, 클라이언트 Swift, 클라이언트 Qt C++)에서 함께 검토한 결과입니다.
각 취약점은 **① 위치 → ② 시나리오 → ③ 영향 → ④ 권장 조치** 형태로 정리했습니다.

---

## 0. TL;DR (요약)

- **CRITICAL**: 서버와 Swift 클라이언트의 `serveFileTransferData` 경로에서 `FileTransferSnapshot.validatePath`가 `String.hasPrefix` 기반이고 경로 정규화를 수행하지 않습니다. 인증을 통과한 상대방이 공유 폴더 경로 뒤에 `../`를 붙여 **호스트의 임의 파일을 읽을 수 있는 Path Traversal**이 존재합니다. Qt 구현은 `std::filesystem::path::lexically_normal()`로 보강되어 있어 해당 경로는 차단되지만, 같은 스냅샷 내부 심볼릭 링크는 여전히 따라갑니다.
- **CRITICAL**: `ClipboardData.data`, `TransferDataChunk.data`, `ClipboardEvent.items` 등 모든 protobuf 메시지에 **크기 및 개수 상한이 전혀 없습니다**. 단일 프레임 길이는 `uint32` 헤더(최대 ~4 GiB)까지 허용되며, 수신부에서 `Data` / `std::vector<uint8_t>`로 전량 버퍼링되므로 인증된 상대방이 간단히 **메모리·디스크 고갈(DoS)** 을 유발할 수 있습니다.
- **HIGH**: `TransferDataChunk.crc32`는 `!= 0` 일 때만 검증합니다. 악의적 상대방이 crc32를 0으로 두면 무결성 검증을 우회할 수 있습니다. QUIC이 이미 무결성을 제공하지만, "선택적 무결성" 은 애플리케이션 불변식으로 잘못된 설계입니다.
- **HIGH**: `TransferStartNotification.totalSize` 가 수신부에서 강제되지 않습니다. 선언된 값과 무관하게 수신자가 계속 버퍼링/디스크 기록을 수행합니다. 마찬가지로 **디스크 고갈** 과 **Promise 파일 fulfillment 의 과다 쓰기**로 이어질 수 있습니다.
- **HIGH**: 서버가 클라이언트에게 보내는 파일 전송 메타데이터에 **호스트의 절대 경로(예: `/Users/alice/Desktop/…`)** 가 그대로 노출됩니다. 클라이언트 측 디버그 로그, 네트워크 캡처에도 남으며 사용자명 / 디렉터리 구조를 유출합니다.
- **MEDIUM**: 서버의 `handleSubscribeClipboardRequest` 는 `syncDirection` 이 `bidirectional` / `remoteToLocal` 일 때 **클라이언트의 명시적 동의 없이** 자동으로 맞구독을 걸고 클라이언트 클립보드 폴링을 트리거합니다. 정책상 의도된 동작이지만 사용자 동의 UI가 없습니다.
- **MEDIUM**: 디렉터리 리스팅 응답의 `entry.name` 을 `metadata.path + "/" + entry.name` 방식으로 이어붙여 다시 요청하므로, **악의적인 상대방이 `entry.name` 에 `..` 를 넣어** 다른 파일을 재요청할 여지가 있습니다.
- **MEDIUM/LOW**: `PendingFileTransfer` 에서 sparse placeholder 를 `open(…, O_WRONLY)` 로 생성할 때 **`O_NOFOLLOW` 가 없습니다**. 경로 자체는 임시 UUID 하위이지만 방어층이 얇습니다.
- **LOW**: `ClipboardMIMEMapping` 이 알 수 없는 pasteboard 타입을 `"application/x-\(raw)"` 로 wrap 하고, 수신 측에서는 `application/x-` 접두사를 제거해 **임의 UTI 문자열을 재구성** 합니다. Content-type injection 자체는 경로에는 영향이 없으나 적법성 검증이 없어 의도치 않은 pasteboard slot 에 쓰기가 가능합니다.

아래에서 각 항목을 자세히 다룹니다.

---

## 1. 대상 및 위협 모델

### 1.1 컴포넌트 범위

| 타겟 | ClipboardChannel 경로 | TransferChannel 경로 |
| --- | --- | --- |
| NoctilucaServer (Swift) | `NoctilucaServer/feature/clipboard/ClipboardChannel.swift` 외 `ClipboardWatcher.swift`, `FileTransferCoordinator.swift`, `FileTransferMetadata.swift` | `NoctilucaServer/feature/transfer/TransferChannel.swift` |
| NoctilucaClient (Swift) | `NoctilucaClient/NoctilucaClient/core/feature/clipboard/*` | `NoctilucaClient/NoctilucaClient/core/feature/transfer/TransferChannel.swift` |
| NoctilucaClientQt (C++) | `NoctilucaClientQt/src/feature/clipboard/{ClipboardChannel,ClipboardManager}.*`, `ClipboardChannel+{Linux,Windows}.cpp`, `TransferSession.cpp`, `windows/ClipboardFile*` | `NoctilucaClientQt/src/feature/transfer/TransferChannel.*` |
| 공통 msgdef | `SiriusKit/Sources/SiriusKitCore/autogen/msgdef/v1/channels/{clipboard,transfer}.pb.swift`, `channel/msgdef/v1/channels/{clipboard,transfer}+Sirius.swift`, `clipboard+Options.swift` | 동일 |

### 1.2 전제 조건

- 트랜스포트는 QUIC + TLS 1.3 (ALPN `pl.unstabler.sirius`) 입니다. 즉 MITM 도청·위조는 별도 문제로 취급합니다.
- `ChannelManager.shouldAcceptChannelCreation` 은 **인증 완료 이후**에만 활성화됩니다(서버: `NoctilucaClientSession`, 클라이언트: `SiriusClient`). 따라서 아래 모든 취약점은 **Sirius 인증을 통과한 상대방**이 가해자가 됩니다.
- `AppSettings.Security.allowedEntries` / 서버측 `ClipboardSettings.allowFile` 가 정책 게이트입니다. 설정이 꺼져 있으면 ClipboardChannel 자체가 거부되지만, 한 번 허용된 세션은 아래 경로로 추가 권한 상승을 시도할 수 있습니다.

### 1.3 위협 모델

| # | 공격자 | 권한 | 목표 |
| - | ------ | ---- | ---- |
| T1 | 인증된 악성 클라이언트 | 서버에 정상적으로 접속, 클립보드 동기화 허용됨 | 서버의 임의 파일 읽기, 서버 프로세스 메모리/디스크 고갈 |
| T2 | 인증된 악성 서버(또는 서버를 탈취한 공격자) | 클라이언트에 정상적으로 접속한 호스트 | 클라이언트의 임의 파일 읽기, 클라이언트 메모리/디스크 고갈, 클립보드 오염 |
| T3 | 로컬 공격자 | 같은 호스트에서 UID 동일한 다른 프로세스 | PendingFileTransfer 임시 디렉터리 조작, 클립보드 스니핑 |
| T4 | 네트워크 관찰자 | QUIC 메타데이터만 관찰 | 전송된 파일의 존재/크기/이름 유추 |

이 보고서에서는 주로 **T1, T2**에 대한 애플리케이션 계층 취약점을 다룹니다.

### 1.4 프로토콜 표면

```
ClipboardChannel (feature UUID 8A3D9F2E-…)
  0x8001 SubscribeClipboardRequest       (requestId, flags)
  0x8002 SubscribeClipboardResponse      (requestId, isSuccess, subscriptionId?)
  0x8003 UnsubscribeClipboardRequest     (requestId, subscriptionId?)
  0x8004 UnsubscribeClipboardResponse    (requestId, subscriptionId?, isSuccess)
  0x8005 ClipboardEvent                  (subscriptionId, timestamp, items[])
  0x8006 GetClipboardRequest             (requestId)
  0x8007 GetClipboardResponse            (requestId, success, items[])

ClipboardItem.representations[]:
  ClipboardData { contentType, size, data?, flags (ClipboardDataFlags: omitted=0x1) }

TransferChannel (feature UUID 9F4EE026-…)
  0x8001 TransferStartNotification       (name, totalSize, contentType, description)
  0x8002 TransferDataChunk               (sequenceNumber, data, crc32, isEOF)

TransferChannel 인자 (ChannelStartRequest.args):
  [purpose, direction, ...additional]
  purpose ∈ {"clipboard-data", "file-transfer"}
  direction ∈ {"upload", "download"}
  clipboard-data 추가 인자: [itemIndex, reprIndex]
  file-transfer  추가 인자: [fileName, filePath, offset, length]
```

---

## 2. CRITICAL 취약점

### 2.1 `FileTransferSnapshot.validatePath` 의 Path Traversal

**위치**
- 서버 Swift: `NoctilucaServer/feature/clipboard/FileTransferMetadata.swift:69`
- 클라이언트 Swift: `NoctilucaClient/NoctilucaClient/core/feature/clipboard/FileTransferMetadata.swift:69`
- 사용 경로:
  - `NoctilucaServer/feature/clipboard/ClipboardChannel.swift:141 serveFileTransferData`
  - `NoctilucaClient/.../ClipboardChannel.swift:116 serveFileTransferData`

**취약한 코드 (Swift)**

```swift
func validatePath(_ path: String) -> Bool {
    entries.values.contains { metadata in
        if metadata.path == path {
            return true
        }
        if metadata.isDirectory {
            let dirPrefix = metadata.path.hasSuffix("/") ? metadata.path : metadata.path + "/"
            return path.hasPrefix(dirPrefix)
        }
        return false
    }
}
```

**시나리오**

1. 사용자 Alice 가 `/Users/alice/Desktop` 디렉터리를 클립보드로 복사합니다. 서버는 `FileTransferSnapshot` 에 `metadata.path = "/Users/alice/Desktop"`, `isDirectory = true` 로 기록합니다.
2. 인증된 악성 클라이언트(T1)가 `TransferChannel` 을 `purpose=file-transfer, direction=download` 로 열면서 `filePath = "/Users/alice/Desktop/../../etc/passwd"` 를 전달합니다.
3. `validatePath` 호출 시 `"/Users/alice/Desktop/../../etc/passwd".hasPrefix("/Users/alice/Desktop/")` → **true**.
4. 이어지는 검증:
   - `fm.fileExists(atPath:)` 은 내부적으로 `stat(2)` 를 호출해 **OS 가 `..` 를 해석**하므로 `/etc/passwd` 존재가 확인됩니다.
   - `path.resolvingSymlinksInPath()` 는 정규화된 경로(`/etc/passwd`) 를 반환하며 `.typeRegular` 이므로 체크를 통과합니다.
   - 실제 송신은 `transferChannel.writeFromFile(at: path, …)` 로 **정규화되지 않은 원본 URL** 을 `FileHandle(forReadingFrom:)` 에 넘깁니다. FileHandle 은 `..` 및 심볼릭 링크를 OS 수준에서 따라가므로 **`/etc/passwd` 의 내용이 그대로 전송**됩니다.
5. 결과: 서버가 열 수 있는 모든 파일(서버 프로세스의 TCC/샌드박스 범위 내 — 클립보드·스크린 권한 범위에서 흔히 `~/Library`, `/etc`, `/private/var/...` 포함) 을 임의 탈취할 수 있습니다.

동일한 취약점이 **Swift 클라이언트 → 서버 방향** 에도 존재합니다. T2(악성 서버) 가 `file-transfer upload` 를 요청하면 클라이언트 프로세스가 접근 가능한 모든 파일(사용자 홈 디렉터리, iOS 의 경우 앱 샌드박스 내부) 을 읽힐 수 있습니다.

**Qt 구현 비교**

`NoctilucaClientQt/src/feature/clipboard/FileTransferMetadata.hpp:205 FileTransferSnapshot::validatePath` 는 비교 전에 `std::filesystem::path::lexically_normal()` 을 적용합니다.
```cpp
auto normalizedRequestedPath = normalizedPath(path);
…
if (normalizedRequestedPath == normalizedRootPath) return true;
…
if (normalizedRequestedPath.rfind(prefix, 0) == 0) return true;
```
`lexically_normal()` 은 `..` 을 문법적으로 축약하므로 앞서 서술한 Swift 측 우회 경로는 차단됩니다. 다만 **심볼릭 링크는 따라가지 않으므로** 스냅샷 디렉터리 내부에 이미 심볼릭 링크가 있다면 여전히 그것을 따라가며 추가로 `serveFileTransferData` 에서 재차 `lexically_normal()` 만 수행합니다. (심볼릭 링크 내용 읽기는 `std::ifstream` 이 그대로 수행합니다.) 즉 Qt 는 Critical 이 아닌 **LOW** 수준의 잔존 위험으로 낮아집니다.

**영향** — Critical (임의 파일 읽기 via 인증된 원격)

**권장 조치**
1. `validatePath` 를 **정규화 기반 경로 포함 관계** 로 전면 재작성합니다. Swift 는 `URL(fileURLWithPath:).standardizedFileURL.resolvingSymlinksInPath()` 혹은 `URL.canonicalPath` 를 사용하고, 루트 디렉터리도 같은 방식으로 정규화한 뒤 `FilePath.contains(other:)` 혹은 수동 path 부모 포함 관계로 판정해야 합니다.
2. 검증된 경로를 **그대로 `writeFromFile`·`FileHandle` 에 전달** 하세요. 원본 입력 문자열을 다시 쓰면 TOCTOU 및 라벨/본체 분리 취약점이 발생합니다.
3. 추가로 심볼릭 링크 따라가지 않기 위해 `O_NOFOLLOW` / `NSURL` 의 `isDirectoryURL` + `ResourceValue` 조합을 사용하거나 `realpath(3)` 으로 루트 밖으로 벗어나는지 최종 확인합니다.
4. Qt 측도 `std::filesystem::weakly_canonical` 로 **실 심볼릭 링크까지** 정규화한 뒤 루트 안에 있는지 확인하도록 강화합니다.

### 2.2 protobuf 메시지에 크기/개수 상한이 없음

**위치**
- `SiriusKit/Sources/SiriusKitCore/autogen/msgdef/v1/channels/clipboard.pb.swift`
  - `ClipboardData.data: bytes`, `flags: uint32`
  - `ClipboardEvent.items: repeated ClipboardItem`
  - `ClipboardItem.representations: repeated ClipboardData`
- `SiriusKit/.../autogen/msgdef/v1/channels/transfer.pb.swift`
  - `TransferDataChunk.data: bytes`
  - `TransferStartNotification.{name, contentType, description}: string`
- 수신부:
  - `TransferChannel.handleTransferDataChunk`(서버 Swift / 클라이언트 Swift / Qt)
  - `ClipboardChannel.resolveOmittedData`(서버 Swift / 클라이언트 Swift / Qt) – 모든 청크를 `Data` / `std::vector<uint8_t>` 로 누적
  - `TransferChannel.receiveAll`(Qt) – `result.insert(result.end(), ...)` 로 누적
  - `FileTransferCoordinator.downloadFile`(Swift) – `FileHandle.write(chunk)` 로 누적 기록, 중단 조건 없음

**시나리오**

1. T1 혹은 T2 가 `TransferChannel` 을 열고 `TransferStartNotification(totalSize: 0)` 을 보냅니다.
2. 이어서 `TransferDataChunk` 를 `data.size() = 2 GiB` 로 한 번에 전송합니다. protobuf decode 는 프레임 헤더가 허용하는 한(최대 4 GiB) 복원에 성공합니다.
3. 수신 측 `TransferChannel.handleTransferDataChunk` 는 `receivedTotalBytes += chunk.data.count` 만 할 뿐 한계가 없습니다. `resolveOmittedData` 는 그 덩어리를 `data += chunk` 로 그대로 붙여 **수신자 RAM 에 2 GiB 단일 객체** 를 만듭니다. Swift `Data` 의 내부 copy-on-write 로 인해 피크 메모리는 더욱 큽니다.
4. 파일 다운로드 경로(`FileTransferCoordinator.downloadFile`) 는 디스크에 기록하지만 `totalSize` 보다 많이 기록되어도 중단하지 않습니다. 즉 **디스크 고갈** 이 가능합니다.

청크 개수 측면에서도 `ClipboardEvent.items[]` 에 수십만 개를 넣거나, `ClipboardItem.representations[]` 를 과다하게 붙이는 식으로 `resolveAndApplyRemoteItems` 루프에서 한 세션당 **채널 N개를 open** 시키는 것도 가능합니다(N = 생략된 representation 수).

**영향** — Critical (DoS 를 통한 가용성 침해, 또한 피해 큼. RCE 아님)

**권장 조치**
1. SiriusKit 레벨에서 **프레임 최대 길이 상수**(예: 16 MiB) 를 정의하고 `SiriusFrameStreamDecoder` 가 이를 초과하는 프레임을 즉시 error 로 드랍하도록 합니다. 스트리밍이 필요한 경우에는 `TransferDataChunk` 를 여러 개로 나누는 것이 올바른 사용법입니다.
2. `TransferChannel` 에 `maxInFlightBytes` / `maxTotalBytes` 상한을 추가하고 `TransferStartNotification.totalSize` 보다 많이 수신되면 즉시 close 합니다. `totalSize == 0` (= unknown) 인 경로는 디렉터리 리스팅 같은 짧은 응답에만 허용하고 기본 캡(예: 256 KiB) 을 적용합니다.
3. `ClipboardEvent.items`, `ClipboardItem.representations` 에도 개수 상한(예: 16 / 16) 을 두고 초과 시 거부합니다.
4. 개별 `ClipboardData.data` 본문에도 상한을 두고 이보다 큰 representation 은 반드시 `omitted` + TransferChannel 경유로 전송하도록 합니다. 현재 `omitThreshold = 128 KiB` 는 송신측 힌트일 뿐 수신측 강제력이 없습니다.
5. `resolveOmittedData` 는 누적 버퍼 상한을 두어야 하며, 초과 시 채널을 닫고 해당 아이템을 스킵해야 합니다.

---

## 3. HIGH 취약점

### 3.1 `crc32 == 0` 이면 무결성 검사를 건너뜀

**위치**
- `NoctilucaServer/feature/transfer/TransferChannel.swift:254`
- `NoctilucaClient/.../feature/transfer/TransferChannel.swift:244`
- `NoctilucaClientQt/src/feature/transfer/TransferChannel.cpp:380`

```swift
// Swift
if chunk.crc32 != 0 {
    let computedCRC = CRC32Util.compute(chunk.data)
    if computedCRC != chunk.crc32 { … }
}
```
```cpp
// Qt
if (chunk.crc32 != 0) {
    uint32_t computed = computeCRC32(chunk.data);
    if (computed != chunk.crc32) { … }
}
```

**시나리오** — 악의적 상대방이 `crc32 = 0` 으로 모든 청크를 보내면 CRC 검증이 완전히 비활성화됩니다. QUIC 자체가 무결성을 보장하지만, CRC 를 선택적 필드로 둔 설계 의도는 **애플리케이션 레벨에서 빠른 프리 체크** 이므로 송신자가 항상 계산하도록 강제하는 게 맞습니다.

**영향** — High (정책 우회)

**권장 조치**
- `TransferDataChunk.crc32` 를 `required` 필드로 격상하거나, **빈 데이터(`data.empty()`)** 일 때만 `0` 을 허용하도록 수정합니다.
- 혹은 CRC32 는 애플리케이션 레벨에서 불필요하다고 판단한다면 message 에서 제거하고 "QUIC 이 무결성을 보장" 임을 문서화합니다.

### 3.2 `TransferStartNotification.totalSize` 미강제

**위치**
- `NoctilucaServer/feature/transfer/TransferChannel.swift:280 handleTransferComplete`
- 대응되는 클라이언트 Swift 및 Qt 구현

```swift
if let notification = startNotification, notification.totalSize > 0 {
    if receivedTotalBytes != notification.totalSize {
        logger.warning("Total size mismatch: expected \(notification.totalSize), received \(self.receivedTotalBytes)")
    }
}
```

해당 코드는 **불일치를 로그에 남길 뿐 채널을 닫거나 downstream 에 알리지 않습니다.** 즉 수신 버퍼/디스크 쓰기를 제한하는 역할을 전혀 하지 못합니다.

또한 `FileTransferCoordinator.downloadFile` 은 실제 받은 크기와 메타데이터의 `size` 를 사후 비교만 하며, 크기가 작든 크든 그대로 `moveItem` 합니다.

**시나리오** — T2 가 `totalSize = 1024` 라고 알린 뒤 1 GiB 를 보내어 **디스크를 채우거나, 원본과 다른 컨텐츠를 넣어 사용자를 속일 수 있습니다**. 특히 Qt Windows 의 `ClipboardFileContentsStream::waitForReadableBytes` 는 `position + requestedSize` 까지 기다리므로 `metadata.size` 를 믿는 편이며, 받은 바이트가 그에 도달하지 않아도 무한 대기 상태가 됩니다.

**영향** — High (DoS + 사용자 기만)

**권장 조치**
- 수신자는 `totalSize` 가 주어진 경우 `receivedTotalBytes > totalSize` 즉시 채널을 에러 종료합니다.
- `isEOF = true` 인데 `receivedTotalBytes != totalSize` 라면 `FileTransferCoordinator` 는 **결과 파일을 폐기** 해야 합니다. 현재는 로그만 남기고 그대로 저장합니다.
- `totalSize == 0` 의 의미("알 수 없음" vs "0바이트") 를 spec 에 명확히 하고, 알 수 없음 경로에는 별도 상한을 두십시오.

### 3.3 `FileTransferMetadata.path` 노출 (서버 → 클라이언트)

**위치**
- 서버 Swift: `NoctilucaServer/feature/clipboard/FileTransferMetadata.swift:116 FileTransferMetadata.from(fileURL:)`
  → `path: filePath` (e.g. `/Users/alice/Desktop/secret.pdf`)
- 클라이언트 Swift / Qt 측도 동일 구조의 JSON 을 교환

서버가 클립보드에 복사한 파일을 원격에 노출할 때, `ClipboardEvent` 의 representation(`application/x-noc-file-transfer`) 안에 **호스트의 절대 경로** 를 담아 보냅니다. 클라이언트는 이를 UI 에 표기하거나(예: 파일 promise 이름), 디렉터리 listing 재귀 요청(`populateChildren`) 에 사용합니다.

**시나리오** — T1 은 서버에 연결된 상태에서 사용자가 복사하는 모든 파일의 **절대 경로를 그대로 수집** 할 수 있습니다. 이는 다음을 유출합니다:
- 사용자명(`/Users/alice/`), 조직 디렉터리 구조, 팀 공유 경로
- 기밀 프로젝트 이름 (예: `/Users/alice/Projects/secret-m&a/plan.xlsx`)
- 바탕화면에 존재하는 개인 식별 파일명

또한 공격자가 해당 디렉터리 구조를 안 상태에서 **2.1 의 Path Traversal** 을 조합하면 훨씬 정밀하게 target 경로를 지정할 수 있습니다.

**영향** — High (정보 노출 + 다른 취약점 증폭)

**권장 조치**
- `FileTransferMetadata` 를 **불투명한 식별자(opaque token)** 로 전환합니다. 서버가 내부 테이블에 `token → real path` 매핑을 보관하고, 와이어에는 `token`, `displayName`, `size`, `contentType` 만 보냅니다. `TransferChannel` 요청 시에도 `filePath` 대신 `token` 을 전달합니다.
- 짧은 기간(예: 현재 클립보드 세션 동안) 만 유효한 토큰으로 관리하면 2.1 의 Path Traversal 까지 동시에 완화됩니다.

---

## 4. MEDIUM 취약점

### 4.1 악성 디렉터리 리스팅을 통한 재귀 요청 경로 주입

**위치**
- 서버 Swift: `NoctilucaServer/feature/clipboard/FileTransferCoordinator.swift:47 populateChildren`
  ```swift
  let childMetadata = FileTransferMetadata(
      …,
      path: metadata.path + "/" + entry.name,
      …
  )
  ```
- 클라이언트 Swift: `NoctilucaClient/.../FileTransferCoordinator.swift:52`
- Qt: `TransferSession::listDirectory()` 내 `entry.path = metadata.path + "/" + entry.name;`

**시나리오** — 디렉터리 listing 응답은 원격이 보내는 JSON 이며 `DirectoryEntry.name` 은 전혀 검증되지 않습니다. 악의적 피어가 `name = "../../../../etc/passwd"` 를 응답으로 돌려주면, 수신측은 이후 `downloadFile` 에서 해당 path 를 다시 송신측에 요구합니다. 동일 상대방에게 재요청하는 구조이므로 상대가 즉시 위협을 증가시키진 않지만, **수신측 로컬 파일시스템에 저장 시** `destinationURL.appendingPathComponent("../…")` 로 경로 이탈을 시도합니다. macOS `URL.appendingPathComponent` 는 `..` 를 그대로 append 하지 않고 경로에 포함시키는 동작을 하기 때문에 현재 환경에서는 쓰기 자체가 실패할 가능성이 높지만, 플랫폼·버전에 따라 동작이 다르므로 방어적으로 검증해야 합니다.

**영향** — Medium (수신 측 로컬 path 조작 가능성)

**권장 조치**
- `DirectoryEntry.name` 을 수신하면 즉시 `name.contains("/") || name.contains("..") || name.isEmpty` 를 거부합니다.
- 원격 path 재조합은 POSIX 레벨 `PathComponent` 단일 토큰으로 제한합니다. Qt 측도 `std::filesystem::path(name).has_parent_path()` 등을 확인해야 합니다.

### 4.2 자동 맞구독 및 사용자 동의 부재

**위치** — `NoctilucaServer/.../ClipboardChannel.swift:293 handleSubscribeClipboardRequest`

```swift
if settings.syncDirection == .bidirectional || settings.syncDirection == .remoteToLocal {
    try? await self.send(opcode: .subscribeClipboardRequest,
                         message: SubscribeClipboardRequest(requestId: 1, flags: 0))
}
```

- 서버가 클라이언트에게 **자동으로** `SubscribeClipboardRequest` 를 전송하여 클라이언트의 클립보드 이벤트를 받아옵니다.
- 클라이언트는 이를 정책(`SessionSettings.Clipboard.enabled`)만 확인하고 그대로 수락합니다. **사용자 동의 UI 가 없습니다.**
- `requestId = 1` 이 매번 고정되어 있어 중복/재사용 시 추적이 어렵습니다.

**영향** — Medium (정책 우회 + 의도되지 않은 클립보드 전송)

**권장 조치**
- 맞구독은 반드시 **명시적 사용자 설정** 또는 **세션 수락 시 확인 UI** 아래에서만 활성화합니다.
- `requestId` 는 monotonic 카운터로 발급하고, 클라이언트도 서버로부터의 subscribe 요청을 정책 창에 의해 거절/허용할 수 있어야 합니다.
- Qt 클라이언트는 현재 맞구독 요청을 받으면 `_clipboardSettings.enabled` 만 확인하고 수락합니다. 여기도 동일 정책을 적용합니다.

### 4.3 `serveTransferData` 가 subscription 상태를 확인하지 않음

**위치** — `NoctilucaServer/.../ClipboardChannel.swift:113 serveTransferData`, 클라이언트 Swift 동일 구조

```swift
func serveTransferData(_ transferChannel: TransferChannel, itemIndex: Int, representationIndex: Int) {
    Task {
        guard let data = lastSentSnapshot?.get(itemIndex: itemIndex, reprIndex: representationIndex) else { … }
        …
    }
}
```

- 인증된 상대방이라면 누구든 `TransferChannel(clipboard-data)` 을 열어서 `lastSentSnapshot` 의 임의 (item, repr) 인덱스를 요청할 수 있습니다.
- `subscriptionId` / `requestId` 와의 연관 검증이 없습니다.
- 정상 동작에서는 한 번에 하나의 클라이언트만 연결되므로 실질 위험은 낮지만, **`maxConcurrentSessions > 1`** 설정이나 **플러그인 주도의 멀티 세션** 이 존재하는 경우, 한 클라이언트가 다른 세션의 클립보드 스냅샷 인덱스를 추측하여 접근할 수 있습니다.

**영향** — Medium (세션 간 격리 누수 가능성)

**권장 조치**
- `lastSentSnapshot` 을 **세션·채널 단위로 격리** 하고, `serveTransferData` 가 호출될 때 `TransferChannel.clientSession == ClipboardChannel.clientSession` 를 확인합니다.
- item/repr 인덱스 대신 **서버가 발급한 opaque token** 을 사용합니다(3.3 과 동일한 해법).

### 4.4 `PendingFileTransfer.createPlaceholder` 에서 `O_NOFOLLOW` 미사용

**위치**
- 서버 Swift: `NoctilucaServer/feature/clipboard/FileTransferCoordinator.swift:309`
- 클라이언트 Swift: `NoctilucaClient/.../FileTransferCoordinator.swift:265`

```swift
fm.createFile(atPath: url.path, contents: nil)
if metadata.size > 0 {
    let fd = open(url.path, O_WRONLY)   // ← O_NOFOLLOW 없음
    if fd >= 0 {
        ftruncate(fd, off_t(metadata.size))
        close(fd)
    }
}
```

**시나리오** — 임시 디렉터리 하위 `{UUID}/{metadata.name}` 경로에 placeholder 를 만듭니다. 동일 UID 를 가진 로컬 공격자(T3) 가 동일 UUID 를 예측하거나 race 를 걸어 `{UUID}/{metadata.name}` 을 symlink 로 선점할 수 있다면 `O_WRONLY` + `ftruncate` 조합이 임의 파일을 0바이트로 만들 수 있습니다. UUID 는 난수이므로 실질 위험은 낮지만, 방어선으로 `O_NOFOLLOW` 를 추가하는 것은 비용이 없습니다. 또한 `metadata.name` 에 `..` 가 포함되면 `appendingPathComponent` 가 리터럴로 포함시키므로 `url.path` 가 여전히 UUID 디렉터리 밖으로 빠져나갈 수 있습니다(이 부분은 **4.1** 과 이어집니다).

**영향** — Medium (LPE 가 아닌 LPE-근접, 방어-in-depth)

**권장 조치**
- `open(url.path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)` 로 수정합니다.
- 더 안전하게는 UUID 디렉터리를 `openat(dirfd, name, O_WRONLY | O_NOFOLLOW | O_CREAT | O_EXCL)` 로 만들고 name 을 sanitize 합니다.
- `metadata.name` 에서 path separator / `..` 를 엄격히 금지합니다.

### 4.5 Qt Windows `ClipboardFileDataObject` 에서 relative path 검증 부재

**위치** — `NoctilucaClientQt/src/feature/clipboard/windows/ClipboardFileDataObject.cpp`, `ClipboardFileContentsStream.cpp`, `ClipboardChannel+Windows.cpp:43 collectWindowsClipboardEntries`

서버가 응답으로 돌려주는 `child.name` 을 그대로 `joinClipboardRelativePath(parent, child.name)` 으로 이어붙여 `FILEGROUPDESCRIPTORW` 의 `cFileName` 에 사용합니다. 악의적 서버가 `name` 에 `..\\..\\..\\Users\\...` 를 포함하면 Windows Explorer 가 Drop 시점에 `SHFileOperationW` 로 처리하며 **임의 위치에 파일이 생성될 여지** 가 있습니다. 최신 Windows 는 대체로 `..` 를 차단하지만, `FILEDESCRIPTORW.cFileName` 의 검증 책임은 전통적으로 source data object 에 있습니다.

**영향** — Medium (Windows drag-and-drop 경로 이탈 가능성)

**권장 조치**
- `relativePath` 를 생성하기 전에 `std::filesystem::path(name).filename() == name` 을 확인하고, 아닐 경우 Entry 를 drop 합니다.
- Explorer 로 drop 되는 총 파일 수/총 크기에도 명시적 한계를 두십시오.

---

## 5. LOW / 방어-in-depth

### 5.1 `application/x-…` MIME wrap 과 pasteboard slot 주입

**위치** — `ClipboardMIMEMapping.mimeType(for:)`, `pasteboardType(for:)` (Swift server/client, iOS, Qt 공통 개념)

```swift
static func mimeType(for pasteboardType: NSPasteboard.PasteboardType) -> String {
    if let mime = typeToMime[pasteboardType] { return mime }
    return "application/x-\(pasteboardType.rawValue)"
}

static func pasteboardType(for mime: String) -> NSPasteboard.PasteboardType {
    if let type = mimeToType[mime] { return type }
    if mime.hasPrefix("application/x-") {
        let uti = String(mime.dropFirst("application/x-".count))
        return NSPasteboard.PasteboardType(uti)
    }
    return NSPasteboard.PasteboardType(mime)
}
```

**문제** — 송신 측은 임의 UTI 를 `application/x-...` 로 감싸고 수신 측은 그대로 복원합니다. 악의적 상대방이 `application/x-com.apple.ic.filename` 같은 UTI 를 주입해 **수신측 pasteboard 의 특수 슬롯** 에 데이터를 쓸 수 있습니다(예: 특정 앱의 사이드 채널). 또한 `application/x-noc-file-transfer` 콘텐츠 타입은 정상 값이지만, 악의적 원격이 `application/x-file-url` 에 본인이 정의한 URL 을 넣어 수신자의 클립보드에 **임의 `file://` URL** 을 주입하는 것이 가능합니다.

**영향** — Low (사용자 인터랙션 필요, 취약점 연쇄 소지)

**권장 조치**
- **허용 목록 기반** 으로 MIME → pasteboard type 매핑을 좁힙니다(`allowUnknownFormat` 옵션이 있으나 기본값이 `true`).
- 수신 측에서는 `application/x-file-url` 및 기타 파일 URL 계열을 **반드시 `allowFile` 정책과 결합** 해 검증합니다. 현재 iOS 에서는 `allowFile` 체크는 있으나 macOS 수신 측(`setWithFileTransfer`) 에서는 별도의 필터링이 없습니다.

### 5.2 `GetClipboardRequest` 무조건 응답

**위치** — `NoctilucaServer/.../ClipboardChannel.swift:322 handleGetClipboardRequest`

- `settings.enabled` 만 확인하고, **구독 여부·세션 상태에 관계없이** 전체 클립보드 스냅샷을 돌려줍니다.
- `lastSentSnapshot` 과 `lastFileTransferSnapshot` 을 갱신하지 않기 때문에 이어지는 `serveTransferData` 호출이 항상 nil 을 반환하는 일관성 버그가 있지만, 보안 관점에서는 **"한 번의 요청으로 서버 클립보드 전량 덤프"** 가 가능한 부분이 문제입니다.

**영향** — Low (이미 구독이 허용된 경우 추가 정보 노출은 없음)

**권장 조치**
- 최소한 `ClipboardEvent` 송신 시와 동일한 스냅샷 관리(`lastSentSnapshot`) 를 수행해야 `serveTransferData` 가 정상 동작하며, 스냅샷의 수명을 기반으로 **응답 후 N초** 내에만 omitted data 를 다시 요구할 수 있게 제한하세요.
- `handleGetClipboardRequest` 에도 `rate limit` 을 둡니다(예: 500 ms 당 1 회).

### 5.3 디버그 로깅으로 인한 클립보드 내용 노출

**위치** — `ClipboardWatcher+macOS.swift` / `+iOS.swift`, `ClipboardManager`(서버)

```swift
#if DEBUG
logger.info("[DUMP] type: \(type.rawValue) => mime: \(mime), size: \(data.count) bytes")
#endif
```

- 클립보드에 담긴 데이터의 **타입과 크기** 가 디버그 로그(OSLog / 콘솔) 로 유출됩니다. 본문은 기록되지 않지만, 로그 보관 정책에 따라 사용자 프라이버시 이슈가 될 수 있습니다.
- Release 빌드에서는 `#if DEBUG` 에 의해 배제되므로 즉각적인 문제는 아닙니다.

**권장 조치**
- `SiriusLogger` 에 "클립보드" 카테고리에 대한 별도 민감도 레벨을 둬서 metadata 만 남기도록 합니다.

### 5.4 `TransferChannel` open 제한 부재

`ChannelManager.openChannel` 는 `FeatureProvider.createChannel` 을 통해 무제한으로 channel 을 만듭니다. 인증된 상대방이 `TransferChannel` 을 계속 열고 닫으면 서버·클라이언트 모두 **파일 디스크립터·QUIC stream 고갈** 가능성이 있습니다. 특히 `FileTransferCoordinator.downloadFile` 은 임시 파일을 UUID 별로 생성하므로 **inode / tmpfs 고갈** 도 가능합니다.

**권장 조치** — `ClientSession` 당 동시 open TransferChannel 수 상한(`maxActiveTransfers`) 를 둡니다. `AppSettings.Transfer` 에 필드 추가.

### 5.5 Linux FUSE bridge 노출 경로의 permission

`NocFuseBridge` 는 `temp_directory_path / "NoctilucaFuseSession-<uuid>"` 를 기본 mount point 로 사용합니다. FUSE mount option 이 `allow_other` 인지 여부에 따라 **동일 호스트의 다른 사용자가 클립보드 파일을 읽을 수 있는지** 가 결정됩니다. 확인 필요 항목이며, 본 감사 범위에서는 `NocFuseBridge` 구현 코드를 상세히 보지 않았습니다. **기본값을 `user_only`(FUSE `-o default_permissions` 미사용, mount owner 만 접근) 로 확인해 두시기 바랍니다.**

---

## 6. 기타 관찰 사항

### 6.1 Qt Client 는 `serveFileTransferData` / `serveTransferData` 가 FeatureProvider 에서 연결되어 있지 않음

`NoctilucaClientQt/src/feature/NoctilucaFeatureProvider.cpp:120` 에서 Transfer channel 을 생성할 때, Swift 버전과 달리 `channel->onReady = serveFileTransferData(...)` 같은 연결 코드가 없습니다. 결과적으로 **Qt 클라이언트는 local → remote 파일 업로드(서버가 클라이언트 파일을 당겨 오는 시나리오) 를 전혀 처리하지 않고**, 원격이 연 Transfer channel 은 그대로 "receive-only" 상태로 남아 remote 측이 open 만 하고 데이터 없이 타임아웃되는 형태로 보입니다. 이는 **기능적 gap** 이며 보안 관점에서는 T2 경로의 공격 표면이 줄어드는 긍정적 side effect 가 있습니다. 기능 복원 시에는 Swift 측과 동일한 검증 구조(2.1 의 권장 조치 포함) 를 처음부터 적용해야 합니다.

### 6.2 `try!` 사용

- `NoctilucaServer/feature/clipboard/ClipboardWatcher.swift:185`: `let jsonData = try! JSONEncoder().encode(metadata)`
- 동일하게 클라이언트 Swift 의 `ClipboardWatcher+macOS.swift:183`.

JSON 인코딩 실패는 사실상 발생하지 않지만 `try!` 는 크래시 경로이므로 신뢰성 측면에서 `try?` + 로깅으로 전환을 권장합니다. 보안 이슈는 아닙니다.

### 6.3 `expectedSequenceNumber` 는 UInt64, `chunk.sequenceNumber` 는 연속 증가 검증

현재 구현은 **정확히 1씩 증가하지 않으면 즉시 채널을 닫습니다**. 이는 정확성 측면에서는 좋지만, 재전송/재순서 정책이 미래에 추가될 때 breaking change 가 발생할 수 있음을 인지해야 합니다.

### 6.4 `TransferChannel.writeFromFile` 의 `offset` 부호 처리

```swift
if offset > 0 {
    try fileHandle.seek(toOffset: UInt64(offset))
}
```
`offset` 은 `Int64`. 0 보다 작으면 seek 을 건너뛰고 처음부터 읽습니다. `UInt64(offset)` 직접 캐스팅 시 음수면 트랩이 발생할 수 있지만 `offset > 0` 가 앞서 막습니다. 다만 Qt 구현은 **offset 음수를 `throw`** 하므로 일관성이 다릅니다. 실무상 T1/T2 가 `offset = Int64.max - 1` 과 같은 값을 보내면 `fileHandle.seek` 가 실패해 에러가 발생하며 이때 `transferChannel.close()` 가 호출되어 안전하게 종료됩니다. 현재는 방어되나 일관성을 위해 입력 검증을 명시적으로 넣는 편이 좋습니다.

### 6.5 `ChannelAccepts` 단계에서 정책 미반영

`TransferChannel.createIfAccepts(…)` 는 `purpose`, `direction` 만 확인하고 **서버 설정(`TransferSettings.allowX`, `ClipboardSettings.allowFile`) 은 전혀 고려하지 않습니다.** 즉 클립보드 기능이 꺼져 있어도 `TransferChannel` 자체는 열립니다. 이후 `serveTransferData` 가 `lastSentSnapshot` 이 없어 `close()` 하므로 실질 피해는 없지만, **정책 게이트를 `accepts` 레벨에서 먼저 거절** 하는 편이 공격 표면을 줄입니다.

### 6.6 단위 테스트 부재

`NoctilucaServerTests` 에는 ClipboardChannel / TransferChannel 의 경로 검증·크기 한계·CRC 처리·재귀 디렉터리에 대한 테스트가 없습니다. 위 항목을 수정하면서 **의도 기반 테스트(명세 기준)** 를 함께 작성해 주시기 바랍니다. (CLAUDE.md Testing Philosophy 참조)

---

## 7. 권장 대응 우선순위

1. **[즉시]** 2.1 Path Traversal 수정(서버·클라이언트 Swift 공통). Qt 도 `weakly_canonical` 로 보강.
2. **[즉시]** 2.2 protobuf 메시지 크기/개수 상한 도입(SiriusKit 레벨 + 채널별 추가 캡).
3. **[즉시]** 3.3 절대 경로 노출 제거 → opaque token 방식으로 전환. Path Traversal 과 함께 완화됨.
4. **[단기]** 3.1 CRC32 의 선택적 검증 제거, 3.2 totalSize 강제.
5. **[단기]** 4.1 DirectoryEntry.name 검증, 4.3 세션·토큰 기반 serveTransferData 격리.
6. **[단기]** 4.2 맞구독 사용자 동의 UX 추가.
7. **[중기]** 4.4 `O_NOFOLLOW` / openat, 4.5 Windows relative path 검증.
8. **[중기]** 5.1 MIME 허용 목록, 5.2 GetClipboardRequest rate limit, 5.4 TransferChannel 개수 제한, 5.5 FUSE 권한 확인.
9. **[문서]** AGENTS.md / SPEC 에 `TransferDataChunk` 의 `crc32`, `totalSize` 의미, 최대 크기, 동시 채널 수 등의 **불변식** 을 명문화. 모든 타겟이 동일하게 강제할 수 있도록 합니다.

---

## 8. 부록: 점검한 주요 파일 목록

### SiriusKit (공통 msgdef)
- `SiriusKit/Sources/SiriusKitCore/SiriusProtocol.swift` (feature UUID 정의)
- `SiriusKit/Sources/SiriusKitCore/autogen/msgdef/v1/channels/clipboard.pb.swift`
- `SiriusKit/Sources/SiriusKitCore/autogen/msgdef/v1/channels/transfer.pb.swift`
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/clipboard+Sirius.swift`
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/clipboard+Options.swift`
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/transfer+Sirius.swift`

### NoctilucaServer (Swift)
- `NoctilucaServer/feature/NoctilucaFeatureProvider.swift`
- `NoctilucaServer/feature/clipboard/ClipboardChannel.swift`
- `NoctilucaServer/feature/clipboard/ClipboardSubscription.swift`
- `NoctilucaServer/feature/clipboard/ClipboardWatcher.swift`
- `NoctilucaServer/feature/clipboard/FileTransferMetadata.swift`
- `NoctilucaServer/feature/clipboard/FileTransferCoordinator.swift`
- `NoctilucaServer/feature/transfer/TransferChannel.swift`
- `NoctilucaServer/models/settings/ClipboardSettings.swift`
- `NoctilucaServer/models/settings/TransferSettings.swift`

### NoctilucaClient (Swift)
- `NoctilucaClient/NoctilucaClient/core/feature/clipboard/ClipboardChannel.swift`
- `NoctilucaClient/NoctilucaClient/core/feature/clipboard/ClipboardWatcher+macOS.swift`
- `NoctilucaClient/NoctilucaClient/core/feature/clipboard/ClipboardWatcher+iOS.swift`
- `NoctilucaClient/NoctilucaClient/core/feature/clipboard/FileTransferCoordinator.swift`
- `NoctilucaClient/NoctilucaClient/core/feature/clipboard/FileTransferMetadata.swift`
- `NoctilucaClient/NoctilucaClient/core/feature/transfer/TransferChannel.swift`

### NoctilucaClientQt (C++)
- `NoctilucaClientQt/src/feature/NoctilucaFeatureProvider.cpp`
- `NoctilucaClientQt/src/feature/clipboard/ClipboardChannel.{hpp,cpp}`
- `NoctilucaClientQt/src/feature/clipboard/ClipboardChannel+Linux.cpp`
- `NoctilucaClientQt/src/feature/clipboard/ClipboardChannel+Windows.cpp`
- `NoctilucaClientQt/src/feature/clipboard/ClipboardManager+Linux.cpp`
- `NoctilucaClientQt/src/feature/clipboard/FileTransferMetadata.hpp`
- `NoctilucaClientQt/src/feature/clipboard/TransferSession.{hpp,cpp}`
- `NoctilucaClientQt/src/feature/clipboard/windows/ClipboardFileContentsStream.cpp`
- `NoctilucaClientQt/src/feature/transfer/TransferChannel.{hpp,cpp}`

---

_본 보고서는 정적 코드 분석에 의한 결과이며, 실제 exploit PoC 는 포함하지 않았습니다. 각 항목에 대한 수정 PR 을 만들 때에는 "소스 코드에 맞춘 테스트" 가 아닌 **명세/의도 기반 테스트** (CLAUDE.md §3) 를 함께 작성해 주시기 바랍니다._
