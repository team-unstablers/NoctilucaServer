# Gesu (ゲス)

**Gesu** (ゲス, 下種, "scoundrel") is a Swift macro library that dynamically loads
Mach-O objects (frameworks, libraries) and lets you call hidden Private APIs with
minimal ceremony. The name is taken from a Japanese slang word for a base or vulgar
person — fitting for a tool that pokes around where Apple would rather you didn't.

It eliminates the tedious `dlopen(3)` / `dlsym(3)` boilerplate via the Swift 6.0
macro system, letting you declare C-convention private functions as if they were
ordinary Swift methods.

A C++20 counterpart is available at
[NoctilucaClientQt/gesu](../NoctilucaClientQt/gesu) — same idea, implemented with
class templates and a small macro instead of compile-time code generation.

## ✨ Features

- **@PrivateLibrary**: Generates a wrapper class that loads (`dlopen`) and manages
  a library/framework at the given path.
- **#PrivateFunction**: Takes a symbol name and function signature, looks up the
  symbol via `dlsym`, and exposes it as a type-safely cast Swift closure.

## 📦 Installation

Add Gesu to your project via Swift Package Manager. Add the following to the
`dependencies` section of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/unstabler/Gesu.git", from: "1.0.0"), // replace with the actual repository URL
]
```

## 🚀 Usage

### 1. Declaring a private library

Use the `@PrivateLibrary` macro to specify the path to the framework or library
you want to load.

```swift
import Gesu
import CoreGraphics

// Wrapper for accessing CoreGraphics Private APIs
@PrivateLibrary(path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class CGPrivate {
    // Function declarations go here.
}
```

### 2. Mapping functions (`#PrivateFunction`)

Use the `#PrivateFunction` macro to map a C function signature to Swift types.

- **name**: the symbol name to bind (String)
- **args**: a tuple of argument types (must be `@convention(c)`-compatible)
- **ret**: the return type

```swift
@PrivateLibrary(path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class CGPrivate {
    // Original C signature: CGError CGSNewConnection(void *attr, int *outConnectionID);
    #PrivateFunction(
        "CGSNewConnection",
        args: (
            UnsafeMutableRawPointer?.self,  // attr
            UnsafeMutablePointer<Int>.self  // outConnectionID
        ),
        ret: CGError.self
    )

    // Original C signature: int _CGSDefaultConnection(void);
    #PrivateFunction(
        "_CGSDefaultConnection",
        args: (),
        ret: Int.self
    )
}
```

### 3. Loading the library and calling functions

Call `open()` to load the library before using any of its functions. Symbols are
exposed as static properties on the wrapper class.

```swift
do {
    // 1. Load the library (dlopen)
    try CGPrivate.open()

    // 2. Call functions.
    // Symbols may fail to resolve, so they are returned as Optionals.

    // No-argument call
    if let defaultConnID = CGPrivate._CGSDefaultConnection?() {
        print("Default Connection ID: \(defaultConnID)")
    }

    // Call with arguments
    var connectionID: Int = 0
    let result = CGPrivate.CGSNewConnection?(nil, &connectionID)

    if result == .success {
        print("New Connection Created: \(connectionID)")
    }

} catch {
    print("Failed to load library: \(error)")
}
```

## ⚠️ Caveats

- **App Store rejection**: This library exists to call Apple's **Private APIs**.
  Apps that ship with Gesu are very likely to fail App Store review. Use it for
  debugging, research, or in-house distribution only.
- **Safety**: Function pointers are converted via `unsafeBitCast`. If the argument
  or return types declared in `#PrivateFunction` do not match the actual symbol in
  the binary, you will get **memory corruption or crashes** at runtime.
- **Sandbox**: Under the macOS sandbox, certain system-path libraries may fail to
  load, or loaded Private APIs may not function correctly due to entitlement
  restrictions.

## 📝 License

MIT License
