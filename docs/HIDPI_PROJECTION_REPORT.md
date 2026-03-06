# HiDPI 프로젝션 지원 현황 및 수정 사항 보고서

> 작성일: 2026-02-24
> 최종 업데이트: 2026-02-26

## 요약

현재 Noctiluca 프로젝션 파이프라인은 HiDPI(Retina) 디스플레이를 사실상 지원하지 않고 있다.
`displayDensity` 옵션(`auto`/`best`/`performance`)이 프로토콜 및 UI 레벨에서 정의되어 있고,
`SCStreamConfiguration.captureResolution`에 반영까지 되지만, 파이프라인의 다른 부분에서
**포인트 단위와 픽셀 단위가 혼용**되고 있어 실제로 HiDPI 캡처가 동작하지 않는다.

문제의 근본 원인은 `NOCScreen.frame`이 **포인트 단위**인데 코드 전반에서 이를 픽셀로 취급하고 있다는 점이며,
이 오해가 캡처 설정, 코덱 협상, 커서 좌표, 프로토콜 메시지까지 전파되고 있다.

---

## 1. 배경: macOS의 좌표 체계

macOS에서 `NSScreen.frame`은 **포인트(point)** 단위를 반환한다.

| 항목 | 값 (맥북 14" 기본 해상도 기준) |
|------|------|
| `NSScreen.frame.size` | (1512, 982) — 포인트 |
| `NSScreen.backingScaleFactor` | 2.0 |
| 실제 프레임버퍼 픽셀 | (3024, 1964) = 포인트 × scaleFactor |

ScreenCaptureKit에서:
- `captureResolution = .nominal` → 포인트 해상도로 캡처 (e.g. 1512×982)
- `captureResolution = .best` → 프레임버퍼 픽셀 해상도로 캡처 (e.g. 3024×1964)
- `SCStreamConfiguration.width/height` → **픽셀 단위를 기대함**. 이 값을 명시하면 해당 크기로 스케일링됨.

---

## 2. 발견된 문제

### 2-1. [핵심] SCStreamConfiguration에 포인트 단위가 들어감

**파일:** `NoctilucaServer/feature/projection/recorder/ScreenCaptureKitScreenRecorder.swift:249~274`

```swift
// (1) captureResolution은 올바르게 설정됨
configuration.captureResolution = .best  // ← OK

// (2) 하지만 width/height를 포인트 단위로 덮어씌움 ← 버그
if let contentSize = try await source.contentSize() {
    configuration.width = Int(contentSize.width)   // 포인트 (e.g. 1512)
    configuration.height = Int(contentSize.height)  // 포인트 (e.g. 982)
}
```

`source.contentSize()`는 `NOCScreen.frame.size`를 반환하는데, 이것이 포인트 단위이다.
`SCStreamConfiguration.width/height`는 픽셀 단위를 기대하므로,
**`captureResolution = .best`를 설정해도 포인트 크기로 다운스케일되어 HiDPI 캡처가 무효화된다.**

**수정 방향:**
`displayDensity`가 `.best`일 때는 `contentSize * scaleFactor`를 `width/height`에 설정해야 한다.
또는 `width/height`를 아예 설정하지 않고 SCStreamConfiguration이 `captureResolution`에 따라
자동으로 결정하도록 위임할 수도 있다 (이 경우 동작을 검증해야 함).

### 2-2. [핵심] 코덱 협상 시 사이즈가 포인트 단위

**파일:** `NoctilucaServer/feature/projection/ProjectionChannel.swift:246~255`

```swift
let contentSize = await request.viewport.contentSize  // ← 포인트 단위

negotiatedCodec = Codec(
    fourCC: negotiatedCodec.fourCC,
    frameRate: negotiatedCodec.frameRate,
    size: contentSize,   // ← 클라이언트에게 포인트 사이즈가 전달됨
    ...
)
```

`ProjectionSessionCreatedEvent`를 통해 클라이언트에 전송되는 `negotiatedCodec.size`가 포인트이다.
클라이언트는 이 값을 실제 비디오 프레임 크기로 간주하므로, HiDPI 캡처 시
**비디오 프레임(픽셀)과 코덱 사이즈(포인트)가 불일치**하게 된다.

**수정 방향:**
`displayDensity` 옵션에 따라 `contentSize`를 적절히 스케일링하여 코덱의 `size`를 설정해야 한다.
이를 위해 해당 디스플레이의 `scaleFactor`를 참조해야 한다.

### 2-3. ~~NOCScreen.frame 문서가 잘못되어 있음~~ ✅ 수정 완료

**파일:** `NoctilucaServer/projection/NOCScreen.swift`

문서가 "디스플레이 해상도 (픽셀 단위)"로 되어 있었으나, 실제로는 포인트 단위였다.

**적용된 수정:**
- `frame` 문서를 "뷰포트 사이즈 (포인트 단위)"로 정정

### 2-4. ~~localViewport 의미가 불명확~~ ✅ 수정 완료

**파일:** `NoctilucaServer/projection/NOCScreen.swift`

의미가 불명확했던 `localViewport`가 제거되고, 목적이 명확한 필드로 교체되었다.

**적용된 수정:**
- `localViewport` → `displayResolution`으로 교체 (실제 디스플레이 픽셀 해상도)
- `CGDisplayCopyDisplayMode`를 통해 실제 픽셀 크기(`pixelWidth/pixelHeight`)를 가져옴
- `scaleFactor`를 `backingScaleFactor` 대신 `displayResolution / frame.size`로 계산하도록 변경

### 2-5. ~~[프로토콜] DisplayInfo에 scaleFactor 필드가 없음~~ ✅ 수정 완료

**파일:** `displayman.proto` / `displayman.pb.swift` / `displayman+Sirius.swift`

`DisplayInfo`에 `scaleFactor` 필드가 없어 클라이언트가 HiDPI 여부를 판단할 수 없었다.

**적용된 수정:**
- `DisplayInfo`에 `float scaleFactor` 필드 추가 (field number 11)
- Swift 래퍼에서 `scaleFactor == 0.0`일 때 `1.0`으로 폴백 (하위 호환성)
- `bounds`는 **포인트 단위를 유지**하고, `scaleFactor`를 별도 필드로 제공하는 방식으로 결정됨

> **참고 (미완료):** `displayman.pb.swift`의 `bounds` 필드 주석이 아직 "디스플레이의 픽셀 단위 너비/높이"로
> 되어 있다. proto 원본 주석을 "뷰포트 단위 (포인트)"로 수정해야 한다.

### 2-6. ~~buildDisplayInfo에서 bounds를 포인트로 전송~~ ✅ 수정 완료

**파일:** `NoctilucaServer/feature/projection/ProjectionChannel+displayman.swift`

`bounds`는 포인트 단위를 유지하되, `scaleFactor`를 함께 전송하는 방식으로 결정되었다.

**적용된 수정:**
- `buildDisplayInfo`에서 `scaleFactor: Float(screen.scaleFactor)` 포함
- disconnected 이벤트의 minimal DisplayInfo에서는 `scaleFactor: 1.0` 기본값 사용

### 2-7. 커서 좌표가 HiDPI 캡처 시 비디오 프레임과 불일치

**파일:** `NoctilucaServer/projection/CursorStateHolder.swift`

`CursorState.relativePosition`은 다음 경로로 계산된다:

1. `NSEvent.mouseLocation` → 포인트 단위
2. `toX11GlobalCoordinate()` → `NOCScreen.frame` 기준 변환 → 포인트
3. `relativePosition` → 해당 디스플레이 origin 기준 상대 좌표 → 포인트

현재 `displayDensity = .performance` (=1x)이면 비디오 프레임도 포인트 크기이므로
비율이 맞아서 **문제가 드러나지 않는다.**

하지만 `displayDensity = .best`로 HiDPI 캡처를 하면:
- 비디오 프레임 크기: 3024 × 1964 (픽셀)
- 커서 좌표: 0~1512, 0~982 범위 (포인트)

클라이언트가 커서 위치를 비디오 프레임 위에 오버레이할 때,
**커서가 좌상단 1/4 영역에만 나타나는** 문제가 발생할 수 있다.

**수정 방향:**
커서 좌표를 전송할 때 사용하는 `sourceSize` (정규화 기준)를 비디오 프레임의 실제 픽셀 크기와 맞춰야 한다.
또는 커서 좌표 자체를 0.0~1.0 정규화된 값으로 변환하여 전송하는 방법도 있다.

---

## 3. 영향을 받는 파일 목록

| 파일 | 수정 종류 | 상태 |
|------|-----------|------|
| `displayman.proto` | **프로토콜 변경** | ✅ `scaleFactor` 필드 추가 완료 (bounds 주석 수정은 미완료) |
| `displayman.pb.swift` (자동생성) | 재생성 | ✅ 완료 |
| `displayman+Sirius.swift` (자동생성) | 재생성 | ✅ 완료 (0.0→1.0 폴백 포함) |
| `NOCScreen.swift` | 리팩토링 | ✅ 완료 (문서 정정, `localViewport`→`displayResolution`, scaleFactor 재계산) |
| `ScreenCaptureKitScreenRecorder.swift` | **핵심 수정** | ❌ 미완료 — width/height에 scaleFactor 반영 필요 |
| `ProjectionChannel.swift` | **핵심 수정** | ❌ 미완료 — negotiatedCodec.size에 scaleFactor 반영 필요 |
| `ProjectionChannel+displayman.swift` | 수정 | ✅ 완료 (`scaleFactor` 전송) |
| `CursorStateHolder.swift` | 수정 | ❌ 미완료 — HiDPI 시 좌표 스케일링 또는 정규화 |
| (C++ 클라이언트 측) | 반영 | ❌ 미완료 — proto 변경에 따른 DisplayInfo 처리 업데이트 |
| (Swift 클라이언트 측) | 반영 | ❌ 미완료 — 코덱 사이즈/커서 좌표 해석 수정 |

---

## 4. 권장 수정 순서

### Phase 1: 프로토콜 결정 (수동 작업 필요) — ✅ 완료

- ✅ `DisplayInfo.bounds`의 단위를 **포인트로 확정**, `scaleFactor`를 별도 필드로 제공
- ✅ `displayman.proto`에 `scaleFactor` 필드 추가 (field number 11)
- ✅ protobuf 코드 재생성 완료
- ⚠️ `bounds` 필드의 proto 주석이 아직 "픽셀 단위"로 되어 있음 → 수정 필요

### Phase 2: 서버 핵심 수정 — 🔧 진행 중

1. ✅ `NOCScreen.swift` 문서 수정 + `localViewport`→`displayResolution` 리팩토링
2. ❌ `ScreenCaptureKitScreenRecorder.swift`에서 `displayDensity`에 따라 `width/height`를 적절히 설정
3. ❌ `ProjectionChannel.swift`에서 `negotiatedCodec.size`를 실제 캡처 해상도에 맞게 설정
4. ✅ `ProjectionChannel+displayman.swift`에서 `DisplayInfo`에 `scaleFactor` 포함

### Phase 3: 커서 좌표 수정 — ❌ 미착수

1. `CursorStateHolder`에서 좌표 전송 시 HiDPI 보정 적용
2. 또는 커서 좌표를 정규화(0.0~1.0) 방식으로 변경

### Phase 4: 클라이언트 반영 — ❌ 미착수

1. Swift 클라이언트: `DisplayInfo.scaleFactor` 처리, 코덱 사이즈 해석 수정
2. C++/Qt 클라이언트: 동일한 변경 반영

---

## 5. 참고: 현재 동작하는 이유

`displayDensity`의 기본값이 `auto`이고, `captureResolution = .automatic`에서
SCStreamConfiguration의 `width/height`가 포인트로 설정되면 ScreenCaptureKit이
포인트 해상도(=nominal)로 캡처한다.

즉, **의도치 않게 항상 1x로 캡처**되고 있으며, 모든 좌표/사이즈가 포인트 단위로 일관되어 있기 때문에
커서 위치나 종횡비 등은 문제없이 보이는 것이다.

`displayDensity = .best`를 선택했을 때만 문제가 드러나며, 현재 이 설정은 사실상 무시되고 있다.
