# macOS 가상 디스플레이 유틸리티 리서치 보고서

> 작성일: 2026-03-21
> 목적: macOS에서 가상 디스플레이를 생성하는 오픈소스 유틸리티의 구현 방식 분석

---

## 요약

macOS에서 가상 디스플레이를 만드는 접근법은 크게 **세 가지 세대**로 나뉜다.

| 세대 | 접근법 | 대표 프로젝트 | macOS 호환성 |
|------|--------|-------------|-------------|
| 1세대 | IOKit 커널 확장 (kext) | displayx, macos-virtual-display | 10.6~12 (kext 지원 종료로 사실상 폐기) |
| 2세대 | CoreDisplay Private API | BetterDummy, FluffyDisplay | 11~13 (일부) |
| 3세대 | CGVirtualDisplay Private API | DeskPad, BetterDisplay, Lumen, node-mac-virtual-display, KhaosT/CGVirtualDisplay | 14+ (Sonoma 이상) |

**현재 활발히 사용되는 방식은 3세대 `CGVirtualDisplay` Private API이다.** Apple이 macOS Sonoma(14)부터 도입한 이 API는 커널 확장 없이 유저스페이스에서 가상 디스플레이를 생성할 수 있어, Sidecar/Luna Display 같은 기능을 서드파티에서도 구현할 수 있게 해준다.

---

## 1. CGVirtualDisplay Private API (3세대, 현재 주류)

### API 구조

`CGVirtualDisplay`는 CoreGraphics 프레임워크에 포함된 **비공개(Private) Objective-C 클래스**다. class-dump으로 역엔지니어링된 헤더(`CGVirtualDisplay.h`)를 통해 구조가 알려져 있다.

**핵심 클래스:**

- **`CGVirtualDisplayDescriptor`** — 가상 디스플레이의 속성을 기술 (해상도, 물리 크기, 벤더/제품 ID 등)
- **`CGVirtualDisplayMode`** — 디스플레이 모드 정의 (해상도 + 리프레시 레이트)
- **`CGVirtualDisplaySettings`** — 적용할 모드 목록 등 설정
- **`CGVirtualDisplay`** — 실제 가상 디스플레이 인스턴스

**주요 프로퍼티 (readonly):**

```
vendorID, productID, serialNum    // 가상 디스플레이 식별
name (NSString)                    // 디스플레이 이름
sizeInMillimeters (CGSize)         // 물리 크기 (밀리미터 단위)
maxPixelsWide, maxPixelsHigh       // 최대 해상도
redPrimary, greenPrimary, bluePrimary, whitePoint  // 색상 정보
displayID                          // 시스템 디스플레이 ID
hiDPI (BOOL)                       // Retina 지원 여부
modes (NSArray)                    // 지원 모드 목록
```

**메서드:**

```objc
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
- (void)dealloc;
```

### 가상 디스플레이 생성 흐름

1. `CGVirtualDisplayDescriptor` 생성 — 해상도, 물리 크기, 벤더/제품 ID 설정
2. `CGVirtualDisplayMode` 배열 생성 — Native 해상도 + Retina 변환 모드 (예: 3840×2160 native + 1920×1080@2x)
3. `CGVirtualDisplay` 객체 생성 (`initWithDescriptor:`)
4. `CGVirtualDisplaySettings`에 모드 적용 (`applySettings:`)
5. `SLSConfigureDisplayEnabled` (SkyLight Private API) 호출로 디스플레이 활성화
6. (선택) `CGDisplaySetDisplayMode`로 원하는 모드 전환

### 제약 사항

- **macOS 14+ (Sonoma) 이상에서만 동작**
- **Private API** — App Store 배포 불가, Apple이 언제든 변경/제거 가능
- **TCC 제약** — 메인 프로세스에서 직접 생성 시 WindowServer 등록 문제 발생, 별도 서브프로세스에서 생성해야 하는 경우가 있음
- **물리 크기 검증** — 선언한 물리 크기 대비 픽셀 밀도가 임계값을 초과하면 생성 거부됨 (예: 27인치 환산 597×336mm 설정 시 4K까지 지원)

### 이 API를 사용하는 프로젝트

#### DeskPad (Stengo/DeskPad)

- **언어:** Swift 82.9%, Objective-C 17.1%
- **목적:** 화면 공유용 가상 모니터 — 앱 실행 = 모니터 연결과 동일
- **구현:** CGVirtualDisplay로 가상 디스플레이 생성, 앱 윈도우에 미러링하여 표시
- **특징:** 커널 확장 없이 유저스페이스에서 동작, 시스템 환경설정에서 해상도 변경 가능
- **라이선스:** MIT
- **설치:** `brew install --cask deskpad`
- **GitHub:** https://github.com/Stengo/DeskPad

#### KhaosT/CGVirtualDisplay (레퍼런스 예제)

- **언어:** Objective-C 57.9%, Swift 42.1%
- **목적:** CGVirtualDisplay API 사용법을 보여주는 예제 코드
- **구조:** `CGVirtualDisplayPrivate.h` (역엔지니어링된 헤더) + Swift/ObjC 구현
- **특징:** Private API의 브릿징 헤더와 기본 사용 패턴을 보여주는 최소한의 예제
- **라이선스:** Apache 2.0
- **GitHub:** https://github.com/KhaosT/CGVirtualDisplay

#### node-mac-virtual-display (enfp-dev-studio)

- **언어:** Objective-C++ 55.7%, TypeScript 13.4%, Shell 21.7%
- **목적:** Node.js에서 macOS 가상 디스플레이를 제어하는 네이티브 모듈
- **사용 API:** CoreGraphics + CoreDisplay
- **기능:** 가상 디스플레이 생성/파괴, 해상도/리프레시레이트 설정, 미러/확장 모드 전환, 디스플레이 이름 지정
- **최소 요구:** macOS 10.14+, Node.js 12+
- **GitHub:** https://github.com/enfp-dev-studio/node-mac-virtual-display

#### BetterDisplay (waydabber/BetterDisplay)

- **상태:** 클로즈드 소스 (바이너리 배포), GitHub에서 이슈/릴리즈 관리
- **목적:** macOS 디스플레이 종합 관리 (HiDPI 스케일링, XDR/HDR 밝기, DDC 제어, 가상 스크린 등)
- **가상 디스플레이 기능:** 다양한 종횡비/해상도의 가상 스크린 무제한 생성, 헤드리스 Mac에서 원격 접속용 해상도 설정
- **전신:** BetterDummy (오픈소스였으나 BetterDisplay로 통합 후 클로즈드 전환)
- **가격:** 무료 기능 + Pro 라이선스 $21.99
- **호환:** macOS 13.2+ (Ventura 이상)
- **GitHub:** https://github.com/waydabber/BetterDisplay

#### Lumen (Sunshine/Moonlight macOS 포크)

- **목적:** Apple Silicon Mac용 네이티브 게임 스트리밍 (Sunshine 포크)
- **가상 디스플레이 구현:** 클라이언트 연결 시 요청 해상도/리프레시레이트에 맞는 가상 디스플레이 자동 생성, 연결 해제 시 자동 파괴
- **구현 특이사항:**
  - TCC/WindowServer 제약으로 `vd_helper`라는 별도 서브프로세스에서 가상 디스플레이 생성
  - 물리 크기를 27인치 모니터(597×336mm)로 고정하여 4K까지 거부 없이 생성
  - `SLSConfigureDisplayEnabled`로 활성화 후 `CGDisplaySetDisplayMode`로 1x 네이티브 모드 전환 (Retina 2x 스케일링 방지)
- **GitHub:** https://github.com/trollzem/Lumen

---

## 2. CoreDisplay / undocumented CoreGraphics API (2세대)

### FluffyDisplay (tml1024/FluffyDisplay)

- **언어:** Swift 58.5%, Objective-C 41.5%
- **목적:** Mac 간 Screen Sharing을 위한 가상 디스플레이 생성
- **사용 API:** 비공개 CoreGraphics API (구체적 클래스명 미공개, CGVirtualDisplay와는 다른 구형 API 추정)
- **필수 권한:** `com.apple.security.temporary-exception.mach-lookup.global-name` entitlement
- **특징:** 메뉴바 앱으로 동작, VNC(Screen Sharing) 연동, P2P 자동 탐색
- **제약:** App Store 배포 불가, "유령 커서" 아티팩트 발생
- **라이선스:** 비명시
- **GitHub:** https://github.com/tml1024/FluffyDisplay

### BetterDummy (waydabber/BetterDummy, 현재 아카이브됨)

- **언어:** Swift
- **목적:** Apple Silicon/Intel Mac에서 커스텀 HiDPI 해상도를 위한 소프트웨어 더미 디스플레이 어댑터
- **구현:** 가상 더미 디스플레이를 생성한 뒤, 실제 디스플레이의 미러 소스로 활용하여 원하는 HiDPI 해상도 달성
- **상태:** BetterDisplay로 통합/아카이브됨
- **GitHub (포크 다수):** https://github.com/ZhipingYang/BetterDummy (원본은 waydabber가 BetterDisplay로 전환)

---

## 3. IOKit 커널 확장 (1세대, 레거시)

### displayx (tSoniq/displayx)

- **언어:** C++ 82.6%, Objective-C++ 10.8%
- **목적:** macOS 가상 디스플레이 드라이버 (연구/학술 목적)
- **구현:**
  - IOKit 커널 확장 (.kext) 기반
  - `DisplayXFBInterface` C++ 클래스가 메인 인터페이스
  - Quartz DisplayStream API로 가상 디스플레이 콘텐츠 캡처
  - 커널 확장 설치 → 리부트 → 앱에서 디스플레이 설정 제어
- **호환:** macOS 10.6~10.x (Apple이 kext 지원을 deprecate하면서 사실상 사용 불가)
- **라이선스:** 독점적 (연구/학술용만 허용)
- **GitHub:** https://github.com/tSoniq/displayx

### macos-virtual-display (miolini)

- **언어:** C++ 79.2%, Objective-C 20.4%
- **목적:** Sidecar/Duet Display/Luna Display와 유사한 기능 구현
- **구현:**
  - IOKit 커널 확장 (`EWProxyFramebufferDriver`) 기반
  - `EWProxyFrameBufferFBuffer` — 가상 프레임버퍼 관리
  - `EWProxyFrameBufferClient` — 프로세스 간 통신
  - 설치: kext + framework 파일을 시스템 라이브러리에 복사 → 리부트
  - Screen Sharing(VNC) 연동으로 원격 모니터 시뮬레이션
- **라이선스:** BSD-3-Clause
- **GitHub:** https://github.com/miolini/macos-virtual-display

---

## 4. 외부 참조: Chromium의 CGVirtualDisplay 활용

Chromium 프로젝트는 자동화 테스트를 위해 `VirtualDisplayUtilMac` 클래스에서 `CGVirtualDisplay` API를 사용한다. 이는 멀티 스크린 환경의 통합 테스트에서 실제 모니터 없이 가상 디스플레이를 생성하는 용도로, API 사용법의 또 다른 레퍼런스가 된다.

소스 위치: `ui/display/mac/test/virtual_display_mac_util.mm`

---

## 5. Noctiluca 관점에서의 시사점

| 고려 사항 | 분석 |
|-----------|------|
| **헤드리스 Mac 지원** | Noctiluca Server가 헤드리스 Mac에서 동작할 때, 물리 디스플레이 없이도 화면 캡처(ScreenCaptureKit)가 작동하려면 가상 디스플레이가 필요할 수 있음 |
| **해상도 매칭** | Lumen처럼 클라이언트 요청 해상도에 맞는 가상 디스플레이를 동적 생성하면 최적의 스트리밍 품질 달성 가능 |
| **API 안정성 리스크** | CGVirtualDisplay는 Private API이므로 macOS 업데이트 시 동작이 변경될 수 있음. Noctiluca도 Private API(Gesu) 사용 경험이 있으므로 리스크 관리 가능할 것 |
| **TCC 서브프로세스 패턴** | Lumen의 `vd_helper` 서브프로세스 패턴은 Noctiluca Server에서도 참고할 만한 아키텍처 |
| **물리 크기 제약** | 4K 이상 해상도 지원 시 물리 크기 선언값에 주의 필요 (27인치 기준 597×336mm이 안전한 값) |

---

## Sources

- [KhaosT/CGVirtualDisplay](https://github.com/KhaosT/CGVirtualDisplay) — CGVirtualDisplay API 레퍼런스 예제
- [Stengo/DeskPad](https://github.com/Stengo/DeskPad) — 화면 공유용 가상 모니터
- [enfp-dev-studio/node-mac-virtual-display](https://github.com/enfp-dev-studio/node-mac-virtual-display) — Node.js 가상 디스플레이 모듈
- [waydabber/BetterDisplay](https://github.com/waydabber/BetterDisplay) — macOS 디스플레이 종합 관리
- [tml1024/FluffyDisplay](https://github.com/tml1024/FluffyDisplay) — Screen Sharing용 가상 디스플레이
- [miolini/macos-virtual-display](https://github.com/miolini/macos-virtual-display) — IOKit kext 기반 가상 디스플레이
- [tSoniq/displayx](https://github.com/tSoniq/displayx) — 가상 디스플레이 드라이버 (학술용)
- [trollzem/Lumen](https://github.com/trollzem/Lumen) — Sunshine 포크, Apple Silicon 게임 스트리밍
- [w0lfschild/macOS_headers - CGVirtualDisplay.h](https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/CoreGraphics/1336/CGVirtualDisplay.h) — 역엔지니어링된 API 헤더
- [Chromium virtual_display_mac_util.mm](https://source.chromium.org/chromium/chromium/src/+/main:ui/display/mac/test/virtual_display_mac_util.mm) — Chromium의 CGVirtualDisplay 활용
