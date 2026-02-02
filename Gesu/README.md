# Gesu (ゲス)

**Gesu**(ゲス, 下種)는 '비열한 놈', '천박한 사람'을 뜻하는 일본어 속어에서 따온 이름으로, Mach-O 오브젝트(프레임워크, 라이브러리)를 동적으로 로드하고 숨겨진 Private API를 간편하게 호출할 수 있도록 도와주는 Swift 매크로 라이브러리입니다.

`dlopen(3)` 및 `dlsym(3)`을 사용하는 지루한 보일러플레이트 코드를 Swift 6.0 매크로 시스템을 통해 획기적으로 줄여주며, C 언어 컨벤션으로 작성된 비공개 함수들을 마치 Swift 메서드처럼 정의하고 사용할 수 있게 해줍니다.

## ✨ 주요 기능

- **@PrivateLibrary**: 특정 경로의 라이브러리/프레임워크를 로드(`dlopen`)하고 관리하는 래퍼 클래스를 생성합니다.
- **#PrivateFunction**: 심볼 이름과 함수 시그니처를 입력받아, `dlsym`으로 심볼을 찾아 타입 안전하게 캐스팅된 Swift 클로저로 노출합니다.

## 📦 설치 (Installation)

Swift Package Manager를 통해 프로젝트에 추가할 수 있습니다. `Package.swift`의 `dependencies`에 다음을 추가하세요.

```swift
dependencies: [
    .package(url: "https://github.com/unstabler/Gesu.git", from: "1.0.0"), // URL은 실제 저장소 주소로 변경 필요
]
```

## 🚀 사용법 (Usage)

### 1. Private 라이브러리 정의

`@PrivateLibrary` 매크로를 사용하여 로드할 프레임워크나 라이브러리의 경로를 지정합니다.

```swift
import Gesu
import CoreGraphics

// CoreGraphics의 Private API를 사용하기 위한 래퍼 정의
@PrivateLibrary(path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class CGPrivate {
    // 여기에 함수 정의가 들어갑니다.
}
```

### 2. 함수 매핑 (#PrivateFunction)

`#PrivateFunction` 매크로를 사용하여 C 함수 시그니처를 Swift 타입으로 매핑합니다.

- **name**: 바인딩할 심볼 이름 (String)
- **args**: 인자 타입들의 튜플 (`@convention(c)` 호환 타입)
- **ret**: 반환 타입

```swift
@PrivateLibrary(path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class CGPrivate {
    // C 함수 원형: CGError CGSNewConnection(void *attr, int *outConnectionID);
    #PrivateFunction(
        "CGSNewConnection",
        args: (
            UnsafeMutableRawPointer?.self,  // attr
            UnsafeMutablePointer<Int>.self  // outConnectionID
        ),
        ret: CGError.self
    )
    
    // C 함수 원형: int _CGSDefaultConnection(void);
    #PrivateFunction(
        "_CGSDefaultConnection",
        args: (),
        ret: Int.self
    )
}
```

### 3. 라이브러리 로드 및 호출

사용하기 전에 `open()`을 호출하여 라이브러리를 로드해야 합니다. 그 후 정의된 정적 프로퍼티를 통해 함수를 호출할 수 있습니다.

```swift
do {
    // 1. 라이브러리 로드 (dlopen)
    try CGPrivate.open()
    
    // 2. 함수 호출
    // 심볼 로드 실패 가능성이 있으므로 Optional로 반환됩니다.
    
    // 인자가 없는 함수 호출
    if let defaultConnID = CGPrivate._CGSDefaultConnection?() {
        print("Default Connection ID: \(defaultConnID)")
    }
    
    // 인자가 있는 함수 호출
    var connectionID: Int = 0
    let result = CGPrivate.CGSNewConnection?(nil, &connectionID)
    
    if result == .success {
        print("New Connection Created: \(connectionID)")
    }
    
} catch {
    print("라이브러리 로드 실패: \(error)")
}
```

## ⚠️ 주의사항

- **App Store 심사 거부**: 이 라이브러리는 Apple의 **Private API**를 호출하기 위한 도구입니다. 이를 사용하여 배포된 앱은 App Store 심사를 통과하지 못할 가능성이 매우 높습니다. 디버깅, 연구, 또는 사내 배포용으로만 사용하십시오.
- **안전성**: `unsafeBitCast`를 사용하여 함수 포인터를 변환합니다. `#PrivateFunction`에 정의한 인자/반환 타입이 실제 바이너리의 심볼과 일치하지 않을 경우, 런타임 시 **메모리 오염이나 크래시**가 발생할 수 있습니다.
- **샌드박스**: macOS 샌드박스 환경에서는 특정 시스템 경로의 라이브러리를 로드하거나, 로드된 Private API가 권한 문제로 동작하지 않을 수 있습니다.

## 📝 라이선스

MIT License
