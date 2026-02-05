## Project Overview

Gesu(ゲス)는 macOS/iOS에서 Private API를 호출하기 위한 Swift 매크로 라이브러리입니다. `dlopen(3)`/`dlsym(3)` 보일러플레이트를 Swift 6.0+ 매크로 시스템으로 간소화합니다.

## Build Commands

```bash
# 빌드
swift build

# 예제 실행 (CGPrivate API 호출 데모)
swift run GesuClient

# 릴리즈 빌드
swift build -c release
```

## Architecture

```
Sources/
├── Gesu/           # 매크로 선언 및 에러 타입 (public API)
│   └── Gesu.swift  # @PrivateLibrary, #PrivateFunction 매크로 선언
├── GesuMacros/     # 매크로 구현 (swift-syntax 기반)
│   ├── GesuMacro.swift           # CompilerPlugin 진입점
│   ├── PrivateLibraryMacro.swift # @PrivateLibrary: dlopen 래퍼 생성
│   └── PrivateFunctionMacro.swift# #PrivateFunction: dlsym 심볼 바인딩
└── GesuClient/     # 사용 예제 (CoreGraphics Private API)
    └── main.swift
```

### Key Macros

- **@PrivateLibrary(path:)**: 클래스에 부착하여 `_libraryHandle` 정적 프로퍼티와 `open()` 메서드를 자동 생성 (MemberMacro)
- **#PrivateFunction(name, args, ret)**: `@convention(c)` typealias와 dlsym 기반 정적 프로퍼티 생성 (DeclarationMacro)

### Generated Code Pattern

```swift
@PrivateLibrary(path: "/path/to/lib")
class MyPrivate {
    #PrivateFunction("FooFunc", args: (Int.self), ret: Void.self)
}
// 생성됨:
// - nonisolated(unsafe) private static var _libraryHandle: UnsafeMutableRawPointer?
// - public static func open() throws { ... dlopen ... }
// - typealias FooFunc_FnType = @convention(c) (Int) -> Void
// - nonisolated(unsafe) static var FooFunc: FooFunc_FnType? = { dlsym(...) }()
```

## Dependencies

- **swift-syntax 602.0.0+**: Swift 매크로 구현에 필요

## Notes

- App Store 배포 불가 (Private API 사용)
- 함수 시그니처 불일치 시 런타임 크래시 위험 (unsafeBitCast 사용)
- macOS 샌드박스 환경에서 특정 라이브러리 로드 제한 가능
