# macOS 입력 소스(언어) 전환 알림 관찰

macOS 호스트의 현재 키보드 입력 소스(한/영, 일본어 IME, 중문 IME 등)가 전환되는
시점을 감지하기 위해 사용할 수 있는 알림(Notification) API 를 정리한다.
HIToolbox (Carbon) 레벨과 AppKit 레벨 두 가지가 존재한다.

## 1. HIToolbox (`Carbon/HIToolbox/TextInputSources.h`)

HIToolbox 의 Text Input Source 서비스(TIS) 는 입력 소스 상태 변경을
**distributed notification** 으로 브로드캐스트한다. 따라서
`NSNotificationCenter.default` / `NotificationCenter.default` 가 아니라
`CFNotificationCenterGetDistributedCenter()` 에 옵저버를 등록해야 한다.

### 주요 알림 이름

| 상수 | 의미 |
| --- | --- |
| `kTISNotifySelectedKeyboardInputSourceChanged` | 현재 선택된 키보드 입력 소스(active input source)가 바뀜. 한/영 전환, IME 전환 등 사용자가 인지하는 "언어 전환" 이벤트가 여기에 해당한다. |
| `kTISNotifyEnabledKeyboardInputSourcesChanged` | 활성화된 입력 소스 목록(System Settings → Keyboard → Input Sources) 자체가 추가/제거됨. 전환 이벤트가 아님에 유의. |

알림 이름은 `CFStringRef` 상수로 export 되어 있으며, payload 의 userInfo 는
일반적으로 비어 있다. 변경 후의 입력 소스는 별도 호출로 조회한다.

```c
TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
// kTISPropertyInputSourceID, kTISPropertyLocalizedName,
// kTISPropertyInputSourceLanguages 등으로 식별
```

### Swift 등록 예

```swift
import Carbon.HIToolbox

final class InputSourceMonitor {
    func start() {
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, name, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<InputSourceMonitor>
                    .fromOpaque(observer).takeUnretainedValue()
                monitor.handleChange()
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }

    private func handleChange() {
        guard let source = TISCopyCurrentKeyboardInputSource()?
            .takeRetainedValue() else { return }
        // TISGetInputSourceProperty(source, kTISPropertyInputSourceID) …
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
```

### 특성

- **시스템 와이드**: 어느 앱이 활성화되어 있어도, 자기 앱이 포커스되어 있지
  않아도 알림이 도착한다.
- **백그라운드 가능**: 데몬/헬퍼/메뉴 익스트라 같이 UI 포커스를 갖지 않는
  프로세스에서도 동작한다.
- **콜백 스레드 주의**: distributed center 의 콜백은 보장된 실행 스레드가
  명시적으로 정의되어 있지 않다. UI/메인-액터 작업이 필요한 경우 명시적으로
  메인으로 dispatch 해야 한다.

## 2. AppKit (`NSTextInputContext`)

AppKit 의 텍스트 입력 컨텍스트가 노출하는 일반 `Notification` 이다.

- `NSTextInputContext.keyboardSelectionDidChangeNotification`
  - Apple Docs: *"Posted after the selected text input source changes."*
  - 일반 `NotificationCenter.default.addObserver(...)` 로 구독.

### 사용 예

```swift
NotificationCenter.default.addObserver(
    forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    // NSTextInputContext.current?.selectedKeyboardInputSource 등으로 조회
}
```

### 특성

- AppKit 수준의 이벤트. 포커스된 텍스트 입력 컨텍스트가 인식하는 변경에
  대응한다.
- AppKit 앱 컨텍스트 안에서 동작하는 것이 전제. 백그라운드 데몬에서는
  적합하지 않다.

## 3. 어떤 것을 선택하는가

| 시나리오 | 권장 |
| --- | --- |
| 호스트 시스템 전역의 입력 소스 전환을 추적 (포커스/활성화 무관) | **HIToolbox `kTISNotifySelectedKeyboardInputSourceChanged`** |
| 백그라운드/헬퍼/메뉴 익스트라에서 동작 | **HIToolbox** |
| 자기 앱이 포커스 가진 상태의 텍스트 입력 컨텍스트만 관심 | **`NSTextInputContext.keyboardSelectionDidChangeNotification`** |
| 활성화된 입력 소스 *목록* 변화(추가/제거) 자체에 반응 | `kTISNotifyEnabledKeyboardInputSourcesChanged` |

NoctilucaServer 는 호스트 머신의 입력 소스를 클라이언트에게 동기화/전달하는
용도이므로, 포커스된 텍스트 필드 유무와 관계없이 시스템 전역 상태를 받아야
한다. 따라서 **HIToolbox 의 distributed notification** 경로가 정답이다.

## 4. 참고

- Apple Developer Documentation
  - `NSTextInputContext.keyboardSelectionDidChangeNotification`
    (https://developer.apple.com/documentation/appkit/nstextinputcontext/keyboardselectiondidchangenotification)
- `<Carbon/HIToolbox/TextInputSources.h>` (SDK 헤더 — `kTISNotify…` 상수,
  `TISCopyCurrentKeyboardInputSource`, `TISGetInputSourceProperty` 등)
