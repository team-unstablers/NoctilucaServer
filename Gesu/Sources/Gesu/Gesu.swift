// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "GesuMacros", type: "StringifyMacro")

// 정의
@attached(member, names: named(_libraryHandle), named(open))
public macro PrivateLibrary(path: String) = #externalMacro(module: "GesuMacros", type: "PrivateLibraryMacro")

@freestanding(declaration, names: arbitrary)
public macro PrivateFunction<Ret, each Arg>(
    _ name: String,
    args: (repeat (each Arg).Type),
    ret: Ret.Type,
    retainedCF: Bool = false
) = #externalMacro(module: "GesuMacros", type: "PrivateFunctionMacro")

public enum PrivateLibraryError: Error {
    case dlopenFailed
}

