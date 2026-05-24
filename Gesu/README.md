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

### 2.5. Handling Create / Copy functions (`retainedCF`)

Core Foundation follows the **Create Rule**: any function whose name contains
`Create` or `Copy` returns a `+1` retained CF reference that the caller is
responsible for releasing. When Apple's headers import such a function, the
Swift compiler bridges this automatically. **Gesu cannot do this** — it binds
via `dlsym`, so the compiler has no header information to derive the rule from.
Returning a plain `CFTypeRef?` from a Copy/Create function therefore leaks one
reference per call.

To handle this safely, pass `retainedCF: true`. Gesu will wrap the return type
in `Unmanaged<T>?`, leaving you to opt into ownership transfer explicitly at the
call site via `.takeRetainedValue()`:

```swift
@PrivateLibrary(path: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
class SkyLightPrivate {
    // Original: CFArrayRef SLSCopyManagedDisplays(int cid);  // Copy rule
    #PrivateFunction(
        "SLSCopyManagedDisplays",
        args: (CGSConnectionID.self,),
        ret: CFArray?.self,
        retainedCF: true              // <- generates `-> Unmanaged<CFArray>?`
    )
}

// Call site: takeRetainedValue() transfers the +1 ownership to Swift ARC.
guard let displays = SkyLightPrivate.SLSCopyManagedDisplays?(connection)?
    .takeRetainedValue() else { return }
```

Use `retainedCF: true` whenever the function name contains `Copy` or `Create`
and returns a CF type. Forgetting it leaks memory; applying it to a non-Create
function will *over*-release and crash, so the function-name convention is the
ground truth.

This option only applies to *direct* return values. Functions that return CF
ownership via an out-parameter (e.g. `SLSCopyWindowProperty(..., CFTypeRef
*out)`) must be handled at the call site with
`Unmanaged.fromOpaque(...).takeRetainedValue()` or equivalent.

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
