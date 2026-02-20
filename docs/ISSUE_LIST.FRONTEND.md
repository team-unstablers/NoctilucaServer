# NoctilucaClient Critical Issues / Unimplemented Features

첫 테스트 출시에 치명적인 위협이 될 수 있는 이슈 5가지 (중요도 순)

### 1. IPv6 미지원 및 주소 파싱 로직 결함 (Critical)
- **위치:** `core/ui/main/viewmodels/SessionWindowViewModel.swift`
- **내용:** `startSession` 메서드에서 서버 주소를 파싱할 때 단순 문자열 분리(`split(separator: ":")`)를 사용하고 있습니다. 이로 인해 `[2001:db8::1]:8282`와 같은 **IPv6 리터럴 주소가 입력되면 파싱이 잘못되어 연결이 불가능**합니다.
- **위협:** App Store 심사 리젝 사유(IPv6-only 네트워크 지원 필수)가 되며, 최신 네트워크 환경에서 접속 불가 문제가 발생합니다. 코드에도 `// FIXME: IPv6 지원하지 않는다`라고 명시되어 있습니다.

### 2. 하드웨어 비디오 디코더 실패 시 Fallback 부재 [done]
- **위치:** `core/feature/projection/decoder/VTVideoDecoder.swift`
- **내용:** `VTVideoDecoder`가 하드웨어 가속 세션 생성에 실패할 경우(`kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder`), 소프트웨어 디코더로 전환하는 로직 없이 에러를 던지고 종료됩니다.
- **위협:** 구형 기기나 다중 세션으로 인해 하드웨어 리소스가 고갈된 경우, **화면이 나오지 않고 블랙 스크린이 표시**됩니다. 코드에 `// FIXME: 이거 해보고 실패하면 소프트웨어 디코드로 fallback하는거 있어야 함`이라고 명시되어 있습니다.

### 3. 멀티 디스플레이 입력 라우팅(Routing) 구현 누락 [done]
- **위치:** `core/feature/hidio/devices/HIDIOAppKitMouse.swift` 및 `RemoteSessionProjectionView.swift`
- **내용:** `HIDIOAppKitPointer`는 `scope` 속성을 통해 입력이 전달될 디스플레이를 지정하지만, 정작 뷰 레이어(`RemoteSessionProjectionView` 등)에서 **이 `scope` 값을 현재 보고 있는 디스플레이 ID로 업데이트해주는 코드가 없습니다.**
- **위협:** 보조 모니터 창(`SubDisplayWindow`)을 띄워놓고 클릭해도, **입력은 무조건 메인 모니터(ID: -1)로 전송**되어 오동작을 일으킵니다.

### 4. macOS 독점 모드(Exclusive Mode) 마우스 가두기 결함
- **위치:** `core/feature/hidio/devices/HIDIOGCMouse.swift`
- **내용:** macOS에서 마우스 입력을 가두기 위해 `CGWarpMouseCursorPosition`을 사용해 커서를 윈도우 중앙으로 강제 이동시키는데, 창이 이동하거나 모니터가 여러 개일 경우에 대한 좌표 보정 로직이 불완전합니다.
- **위협:** 사용자가 창을 이동시키거나 보조 모니터에 창이 있을 때, **마우스 커서가 엉뚱한 위치(예: 다른 모니터)로 튀거나 갇혀서 조작 불능 상태**에 빠질 수 있습니다. 코드에 `// FIXME: 근데, 이렇게 했는데 창이 다른 디스플레이로 이동하면 어떻게 되는거야?`라는 우려가 남겨져 있습니다.

### 5. 오디오 프로젝션 초기화 예외 처리 미비 (Fire-and-Forget) [done]
- **위치:** `core/feature/projection/ProjectionChannel+Session.swift`
- **내용:** `createAudioSession` 메서드가 오디오 요청을 보낸 후, 성공적으로 세션이 생성되었는지 확인하거나 실패 시 재시도/사용자 알림을 주는 피드백 루프가 없습니다.
- **위협:** 오디오 코덱 협상 실패나 네트워크 문제로 오디오 연결이 안 되어도 **사용자는 아무런 에러 메시지 없이 소리만 안 들리는 상황**을 겪게 됩니다. `// TODO: 성공 여부를 감시해야 함` 코멘트가 남아 있습니다.

### 6. 설정 및 자격 증명 저장 실패 무시 (Silent Failure)
- **위치:** `core/models/settings/SettingsStore.swift`, `core/models/session-settings/SessionCredentialsStore.swift`
- **내용:** `save()` 메서드들이 파일 쓰기나 키체인 접근 에러를 `try?`로 무시하거나 로그(`logger.error`)만 남기고 사용자에게 피드백을 주지 않습니다.
- **위협:** 디스크 공간 부족, 권한 문제 등으로 저장이 실패해도 사용자는 성공한 줄 알았다가 나중에 데이터(설정, 비밀번호 등)가 유실된 것을 발견하게 됩니다.

### 7. HIDIO 입력 이벤트 레이트 리미팅 부재
- **위치:** `core/feature/hidio/HIDIOController.swift`
- **내용:** `publisherTaskMain` 루프에서 입력 이벤트를 `AsyncStream`으로 받아 처리하는데, 별도의 속도 제한(Rate Limit)이나 병합(Coalescing) 로직이 없습니다.
- **위협:** 고폴링레이트 마우스(1000Hz+)를 사용하거나 입력이 폭주할 때, 네트워크 큐가 가득 차서 지연이 발생하거나 서버/네트워크에 과도한 부하를 줄 수 있습니다.

### 8. 연락처 삭제 시 키체인 데이터 잔존 (Resource Leak/Security) [done]
- **위치:** `core/models/ContactsStore.swift`
- **내용:** `ContactsStore.remove(id:)` 메서드에서 JSON 파일만 삭제하고, 해당 연락처와 연결된 키체인 아이템(비밀번호 등)을 삭제하는 `SessionCredentialsStore.remove` 호출이 누락되어 있습니다.
- **위협:** 연락처를 삭제해도 민감한 인증 정보가 키체인에 영구적으로 남게 되며, 이는 보안 위험이자 리소스 누수입니다.

### 9. 인증서 고정(Pinning) UI 미구현
- **위치:** `core/ui/session-settings/SecuritySessionSettingsTab.swift`
- **내용:** 보안 설정 탭에 '인증서 고정하기' 토글은 존재하지만, 정작 고정할 인증서 핀(Fingerprint)을 입력하거나 관리하는 UI가 `// FIXME` 상태로 비워져 있습니다.
- **위협:** 사용자가 MITM 공격 방지를 위해 기능을 켜더라도 실제로는 핀을 설정할 수 없어 기능이 무용지물이 됩니다.

### 10. SubDisplayWindow 상태(위치/크기) 미저장
- **위치:** `core/feature/projection/SubDisplayWindow.swift`
- **내용:** 보조 모니터 창을 닫았다가 다시 열면 이전 위치와 크기가 복원되지 않고 항상 화면 중앙/기본 크기로 초기화됩니다. `setFrameAutosaveName` 설정이 누락되어 있습니다.
- **위협:** 멀티 모니터 사용자가 매번 세션을 연결할 때마다 창을 다시 배치해야 하는 심각한 사용성 저하를 초래합니다.

### 11. 설정 파일 로드 시 메인 스레드 블로킹 (UI Freeze)
- **위치:** `core/models/settings/SettingsStore.swift`
- **내용:** `init` 메서드에서 `AppSettings.load()`를 호출하여 JSON 파일을 동기적으로 읽고 파싱합니다. 디스크 I/O가 메인 스레드에서 발생하여 앱 실행 시 일시적인 멈춤(Hitch)을 유발할 수 있습니다. `// TODO: ensure this runs on main thread` 주석이 있습니다.
- **위협:** 앱 초기 실행 속도 저하 및 사용성 저하(버벅임).

### 12. Ping Loop 좀비 타스크 및 타임아웃 부재 [done]
- **위치:** `core/logic/NoctilucaClient.swift`
- **내용:** `pingLoop` 메서드 내 `sendPing()`에 대한 응답(`pongHandler`)을 `withCheckedContinuation`으로 기다리는데, 별도의 타임아웃이 설정되어 있지 않습니다.
- **위협:** 네트워크가 불안정하여 Pong이 오지 않으면 해당 Task는 영원히 대기 상태로 남게 되며(Resource Leak), RTT 업데이트도 영구히 멈춥니다.

### 13. 오디오 디코더 포맷 변경 대응 미비
- **위치:** `core/feature/projection/decoder/OpusAudioDecoder.swift` 등
- **내용:** 오디오 세션 도중 서버가 오디오 샘플 레이트나 채널 구성을 변경할 경우, 디코더나 `AVAudioConverter`를 재설정하는 로직이 없습니다.
- **위협:** 스트림 중간에 포맷이 바뀌면 오디오가 깨지거나(노이즈), 재생이 멈추거나, 컨버터 오류로 인해 앱이 크래시될 수 있습니다.

### 14. TileCompositor 리소스 해제 지연 (Memory Spike)
- **위치:** `core/feature/projection/ProjectionSession.swift`
- **내용:** `ProjectionSession`이 종료될 때 `tileCompositor`를 즉시 `nil`로 설정하지 않고, `deinit`이나 다음 `prepare` 호출 시점에만 정리합니다.
- **위협:** 고해상도 타일링 세션(WebP/ZRLE)을 반복적으로 열고 닫을 때(예: 디스플레이 전환), 비디오 메모리(VRAM) 사용량이 일시적으로 치솟아 메모리 부족 경고나 강제 종료를 유발할 수 있습니다.

### 15. SubDisplayWindow 상태 동기화 부재
- **위치:** `app/macos/ui/session/SubDisplayWindow.swift`
- **내용:** 보조 모니터 윈도우 생성 시점(`init`)에만 타이틀을 설정하고, 이후 디스플레이 이름이 변경되거나 해상도가 바뀌어도 윈도우에 반영되지 않습니다.
- **위협:** 디스플레이 설정이 변경되었을 때 사용자에게 혼란을 줄 수 있습니다 (예: "Display #2"가 "Monitor X"로 바뀌어도 윈도우 제목은 그대로 유지됨).

### 16. `RemoteSession.deinit`의 불안정한 비동기 리소스 정리 (Resource Leak 가능성) [done]
- **위치:** `core/state/RemoteSession.swift`
- **내용:** `deinit` 내에서 `Task`를 띄워 `close()`를 호출하지만, 실행 시점을 보장할 수 없으며 앱 종료 시에는 해당 작업이 완료되기 전에 프로세스가 종료될 수 있습니다.
- **위협:** 소켓이 정상적으로 닫히지 않아 서버 측에 좀비 세션이 남거나, 로컬 리소스(CoreAudio 등)가 제대로 해제되지 않을 수 있습니다.

### 17. SSH 키 자격 증명 추가 시 에러 피드백 부재 (Silent Failure)
- **위치:** `core/ui/session-settings/security/CredentialAddSheet.swift`
- **내용:** `handleSubmit` 메서드에서 개인 키 파싱 실패 시(`try? SSHPrivateKey(...)`) 아무런 에러 메시지 없이 단순히 `return` 합니다.
- **위협:** 사용자는 올바른 키를 입력했다고 생각하고 추가 버튼을 누르지만, 실제로는 아무런 동작도 일어나지 않아 혼란을 겪게 됩니다.

### 18. 입력 설정 초기화 기능 미구현 [done]
- **위치:** `core/ui/settings/InputSettingsTab.swift`
- **내용:** "문제 해결" 섹션의 "입력 관련 설정 초기화" 버튼 액션이 `// settingsStore.resetInputSettings()` 주석 처리되어 있어 실제로 동작하지 않습니다.
- **위협:** 사용자가 입력 설정을 잘못 건드려 조작이 불가능해졌을 때, 앱 데이터를 초기화하지 않고는 복구할 방법이 없습니다.

### 19. `stop()` 메서드의 네트워크 의존성 (Hang 위험) [done]
- **위치:** `core/feature/projection/ProjectionSession.swift`
- **내용:** 세션 종료 시 `controlChannel.send(...)`를 호출하여 서버에 종료 요청을 보내는데, 네트워크가 이미 끊긴 상태라면 타임아웃까지 대기하거나 에러로 인해 종료 프로세스가 지연될 수 있습니다.
- **위협:** 연결이 불안정한 상태에서 창을 닫거나 세션을 종료하려 할 때 UI가 일시적으로 멈추거나(Hang), 즉각적인 피드백을 주지 못할 수 있습니다.

### 20. 디스플레이 스위처 미리보기 미구현
- **위치:** `core/ui/main/sheets/DisplaySwitcherSheet.swift`
- **내용:** 멀티 모니터 전환 UI에서 각 모니터의 실제 화면 대신 검은색 사각형(`Rectangle().fill(.black)`)만 표시됩니다.
- **위협:** "Display 1", "Display 2"와 같이 이름만으로는 구분하기 어려운 환경에서 사용자가 원하는 화면을 직관적으로 선택하기 어렵습니다.
